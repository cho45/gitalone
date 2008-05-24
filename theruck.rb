require "rubygems"
require "rack"

module TheRuck
	class Controller
		GET  = "GET"
		PUT  = "PUT"
		POST = "POST"
		HEAD = "HEAD"

		class << self
			def handlers
				self.instance_variable_get(:@handlers)
			end

			def view(name, klass, opts={})
				define_method(name) do |path|
					i = klass.new(opts).render(path, stash)
					head i.header
					body i.body
				end
			end

			def bind(o, &block)
				handlers = self.instance_variable_get(:@handlers) || []
				case o
				when Hash
					source = o.keys.first
					method = o[source]
					regexp, names = route(source)
				else
					source = o
					method = //
					regexp, names = route(o)
				end

				handler_name = "handler_#{source}"
				define_method(handler_name, block)
				handlers << [
					source,
					regexp,
					method,
					names,
					handler_name
				]
				self.instance_variable_set(:@handlers, handlers)
			end

			def route(str)
				names = []
				paths = str.to_s.split("/", -1)
				regex = paths.empty?? %r|^/$| : Regexp.new(paths.inject("^") {|r,i|
					if i[0] == ?:
						names << i.sub(":", "")
						r << "/([^/]+)"
					else
						r << "/#{i}"
					end
				} + "$")
				[regex, names]
			end
		end

		attr_reader :stash, :params, :env

		def result(env)
			@status, @header, @body = 200, {}, ""
			@stash  = {}
			@env    = env
			@params = env["QUERY_STRING"].split(/[&;]/).inject({}) {|r,pair|
				key, value = pair.split("=", 2).map {|str|
					str.tr("+", " ").gsub(/(?:%[0-9a-fA-F]{2})+/) {
						[Regexp.last_match[0].delete("%")].pack("H*")
					}
				}
				r.update(key => value)
			}

			dispatched = false
			self.class.handlers.each do |source, route, method, names, handler_name|
				if method === env["REQUEST_METHOD"] && route === env["PATH_INFO"]
					@params.update names.zip(Regexp.last_match.captures).inject({}) {|r,(k,v)|
						r.update(k => v)
					}
					$stderr.puts "dispatch #{env["PATH_INFO"]} => #{source} => #{handler_name}"
					dispatched = true
					send(handler_name)
					break
				end
			end

			unless dispatched
				send("handler_404")
			end

			[@status, @header, [@body]]
		end

		def head(name, value=nil)
			case name
			when Numeric
				@status = name.to_i
			when Hash
				@header.update(name)
			else
				@header[name.to_s] = value.to_s
			end
		end

		def body(str)
			@body << str
		end


		bind "404" do
			head 404
			body "404 Not Found"
		end
	end


	class View
		attr_accessor :header, :body

		def initialize(opts={})
			@header = {}
			@body   = ""
		end

		def head(name, value=nil)
			@header[name] = value.to_s
		end

		def body(str="")
			@body << str
		end

		class ErubisEruby < View
			@@templates = {}

			def initialize(opts={})
				require "erubis"
				super
				@opts = {
					:dir => "templates"
				}.update(opts)
				@layout = []
				extend @opts[:helper] if @opts[:helper]
			end

			def render(path, stash)
				@@templates[path] ||= ::Erubis::EscapedEruby.new(File.read("#{@opts[:dir]}/#{path}.html"))
				head "Content-Type", "text/html"
				b = binding
				stash.each {|k,v| eval "#{k} = stash[:#{k}]", b }
				body @layout.inject(@@templates[path].result(binding)) {|content,layout|
					@@templates[layout].result(binding)
				}
				self
			end

			def layout(path=:layout)
				@@templates[path] ||= ::Erubis::EscapedEruby.new(File.read("#{@opts[:dir]}/#{path}.html"))
				@layout << path
			end
		end

		class JSON < View
			def initialize(opts={})
				require "json"
				super
			end

			def render(path, stash)
				head "Content-Type", "text/javascript"
				body ::JSON.dump(stash)
			end
		end
	end
end
