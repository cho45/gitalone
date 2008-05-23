#!/usr/bin/env ruby

require "rubygems"
require "theruck"
include TheRuck

require "mojombo-grit"
require "pathname"
require "ostruct"

class GitAlone < Controller
	def self.call(env)
		new(:dir => "~/project/").result(env)
	end

	def initialize(opts)
		@opts = OpenStruct.new(opts)
		@opts.dir = Pathname.new(@opts.dir).expand_path
	end

	view :html => View::ErubisEruby.new,
	     :json => View::JSON.new

	bind "" do
		stash["repos"] = []

		GC.start
		Pathname.glob("#{@opts.dir}/*/.git/").each do |g|
			repo = Grit::Repo.new(g)
			next unless repo.heads.first
			stash["repos"] << {
				:path => g.parent,
				:repo => repo
			}
		end
		GC.start

		stash["repos"] = stash["repos"].sort_by {|i|
			info = i[:repo].heads.first.commit.to_hash
			info["committed_date"]
		}.reverse

		html :index
	end

	bind "repo/:name" do
		raise "Invalid /" if params["name"].include?("/")
		repo = Grit::Repo.new(@opts.dir + params["name"] + ".git")
		stash["repo"] = repo

		head "Content-Type", "text/plain"
		body params.inspect
		body repo.inspect
		body repo.tags.inspect
		body repo.heads.inspect
		body repo.description
	end

	bind "repo/:name/commit/:hash" do
		body params.inspect
	end

	bind "repo/:name/commits/:head" do
		body params.inspect
	end

	bind "repo/:name/tree/:name" do
		body params.inspect
	end
end

# Rack::Handler::WEBrick.run GitAlone, :Port => 3000

