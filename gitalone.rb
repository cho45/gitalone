#!/usr/bin/env ruby

require "rubygems"
require "theruck"
include TheRuck

require "mojombo-grit"
require "pathname"
require "ostruct"

### --start
module Grit
	class Remote
		attr_reader :name, :repo

		def self.find_all(repo)
			Pathname.glob("#{repo.path}/refs/remotes/*").map { |path|
				Remote.new(repo, path.basename.to_s)
			}
		end

		def initialize(repo, name)
			@repo, @name = repo, name
		end

		def heads
			Pathname("#{@repo.path}/refs/remotes/#{@name}").children.map {|c|
				Grit::Head.new(c.basename.to_s, Grit::Commit.create(@repo, :id => c.read.strip))
			}
		end

		def head(name="master")
			c = Pathname.new("#{@repo.path}/refs/remotes/#{@name}/#{name}")
			Grit::Head.new(c.basename.to_s, Grit::Commit.create(@repo, :id => c.read.strip))
		rescue Errno::ENOENT, Errno::ENOTDIR
			nil
		end
	end

	class Repo
		def remotes
			Remote.find_all(self)
		end
	end
end
### --end

class GitAlone < Controller
	def self.call(env)
		new(:dir => "~/project/").result(env)
	end

	def initialize(opts)
		@opts = OpenStruct.new(opts)
		@opts.dir = Pathname.new(@opts.dir).expand_path
	end

	module Helper
		def gravatar(email, size=30)
			"http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}?s=#{size.to_i}"
		end
	end

	require "digest/md5"
	view :html, View::ErubisEruby, :helper => Helper
	view :json, View::JSON

	bind "" do
		stash[:repos] = []

		GC.start
		Pathname.glob("#{@opts.dir}/*/.git/").each do |g|
			repo = Grit::Repo.new(g)
			next unless repo.heads.first
			stash[:repos] << {
				:path    => g.parent,
				:repo    => repo,
			}
		end
		GC.start

		stash[:repos] = stash[:repos].sort_by {|i|
			info = i[:repo].heads.first.commit.to_hash
			info["committed_date"]
		}.reverse

		html :index
	end

	bind "repo/:name" do
		raise "Invalid /" if params["name"].include?("/")

		head 302
		head "Location", "/repo/#{params["name"]}/tree/master"
		head "Content-Type", "text/plain"
		body "Redirect"
	end

	bind "repo/:name/commit/:hash" do
		body params.inspect
	end

	bind "repo/:name/commits/:head" do
		body params.inspect
	end

	bind "repo/:name/tree/:head" do
		repo = Grit::Repo.new(@opts.dir + params["name"] + ".git")
		stash[:name] = params["name"]
		stash[:head] = params["head"]
		stash[:repo] = repo
		html :tree
	end
end

# Rack::Handler::WEBrick.run GitAlone, :Port => 3000

