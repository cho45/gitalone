#!rackup

require "gitalone"

use Rack::Static, :urls => ["/css", "/img", "/js"], :root => "root"
run GitAlone

