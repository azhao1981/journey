require 'journey/core-ext/hash'
require 'journey/router/utils'
require 'journey/router/strexp'
require 'journey/routes'
require 'journey/formatter'

before = $-w
$-w = false
require 'journey/parser'
$-w = before

require 'journey/route'
require 'journey/path/pattern'

module Journey
  class Router
    class RoutingError < ::StandardError
    end

    VERSION = '1.0.0'

    class NullReq # :nodoc:
      attr_reader :env
      def initialize env
        @env = env
      end

      def request_method
        env['REQUEST_METHOD']
      end

      def [](k); env[k]; end
    end

    attr_reader :request_class, :formatter
    attr_accessor :routes

    def initialize routes, options
      @options       = options
      @params_key    = options[:parameters_key]
      @request_class = options[:request_class] || NullReq
      @routes        = routes
    end

    def call env
      env['PATH_INFO'] = Utils.normalize_path env['PATH_INFO']

      find_routes(env) do |match, parameters, route|
        script_name, path_info, set_params = env.values_at('SCRIPT_NAME',
                                                           'PATH_INFO',
                                                           @params_key)

        unless route.path.anchored
          env['SCRIPT_NAME'] = script_name.to_s + match.to_s
          env['PATH_INFO']   = match.post_match
        end

        env[@params_key] = (set_params || {}).merge parameters

        status, headers, body = route.app.call(env)

        if 'pass' == headers['X-Cascade']
          env['SCRIPT_NAME'] = script_name
          env['PATH_INFO']   = path_info
          env[@params_key]   = set_params
          next
        end

        return [status, headers, body]
      end

      return [404, {'X-Cascade' => 'pass'}, ['Not Found']]
    end

    def recognize req
      find_routes(req.env) do |match, parameters, route|
        unless route.path.anchored
          req.env['SCRIPT_NAME'] = match.to_s
          req.env['PATH_INFO']   = match.post_match.sub(/^([^\/])/, '/\1')
        end

        yield(route, nil, parameters)
      end
    end

    private

    def find_routes env
      addr       = env['REMOTE_ADDR']
      req        = request_class.new env

      routes.each do |r|
        next unless r.constraints.all? { |k,v|
          v === req.send(k)
        }

        next unless r.verb === env['REQUEST_METHOD']
        next if addr && !(r.ip === addr)

        match_data = r.path.match env['PATH_INFO']

        next unless match_data

        match_names = match_data.names.map { |n| n.to_sym }
        info = Hash[match_names.zip(match_data.captures).find_all { |_,y| y }]
        yield(match_data, r.defaults.merge(info), r)
      end
    end
  end
end
