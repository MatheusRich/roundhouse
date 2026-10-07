# CRuby-only Rails::Application#routes surface.
#
# Lobsters' config/application.rb composes absolute URLs via
# `Rails.application.routes.url_helpers.root_url(host:, protocol:)`
# (Story#short_id_url and friends). The shared runtime's Application is
# deliberately empty (NameError over silent stubs); this overlay adds
# the real thing for CRuby: url_helpers resolves against the emitted
# RouteHelpers, and root_url composes protocol://host + root_path.
# Overlay, not shared runtime — the kwarg signature is exactly the
# forwarding shape strict targets refuse (see the kwarg-forwarding gap).
#
# `#routes` returns `RouteSet`, which is Rails' name for this object
# (`ActionDispatch::Routing::RouteSet`). The name must not be
# `RouteTable`: a nested `RouteTable` hides the emitted top-level
# `RouteTable` that `recognize_path` reads.

module ActionController
  # Raised by `recognize_path` for a verb that Rails does not accept.
  # It lives in this overlay and not in runtime/ruby/, so `check` still
  # reports app code that names it. The Rails superclass is
  # `ActionControllerError`, which the runtime does not define.
  class UnknownHttpMethod < StandardError
  end
end

module Rails
  class Application
    def routes
      RouteSet
    end

    module RouteSet
      # `ActionDispatch::Request::HTTP_METHODS`, in the Rails order.
      HTTP_METHODS = %w[
        OPTIONS GET HEAD POST PUT DELETE TRACE CONNECT
        PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK
        VERSION-CONTROL REPORT CHECKOUT CHECKIN UNCHECKOUT MKWORKSPACE UPDATE LABEL MERGE BASELINE-CONTROL MKACTIVITY
        ORDERPATCH ACL SEARCH MKCALENDAR PATCH
      ].freeze

      def self.url_helpers
        UrlHelpers
      end

      # Rails' `recognize_path` for one path. The result has Symbol
      # keys and String values: `:controller`, `:action`, each dynamic
      # segment, and `:format` last. A namespaced controller gives the
      # flat router name (`"admin_posts"`), not the Rails path.
      # `environment[:method]` is the verb, a Symbol or a String in any
      # case, and GET is the default. Other keys have no effect.
      def self.recognize_path(path, environment = {})
        verb = (environment[:method] || "GET").to_s.upcase
        # Rails checks the verb before it matches. The check also keeps
        # out "ANY", which the router uses for a `via: :all` route.
        unless HTTP_METHODS.include?(verb)
          accepted = "#{HTTP_METHODS[0...-1].join(", ")}, and #{HTTP_METHODS.last}"
          raise ActionController::UnknownHttpMethod, "#{verb}, accepted HTTP methods are #{accepted}"
        end
        # Rails ignores the query and the fragment.
        bare = path.split(/[?#]/, 2).first.to_s
        matched = ActionDispatch::Router.match(verb, bare, table)
        raise ActionController::RoutingError, "No route matches #{path.inspect}" if matched.nil?

        params = matched.path_params
        recognized = { controller: matched.controller.to_s, action: matched.action.to_s }
        params.each { |name, value| recognized[name.to_sym] = value unless name == "format" }
        recognized[:format] = params["format"] if params.key?("format")
        recognized
      end

      # The table that the dispatcher composes, built once.
      # `RouteTable.table` makes new Route objects on each call. The
      # routes emit defines `RouteTable.root` only for an app with a
      # root route.
      def self.table
        @table ||= (RouteTable.respond_to?(:root) ? [RouteTable.root] : []) +
                   RouteTable.table + ActiveStorage::Routes.table
      end
    end

    module UrlHelpers
      def self.root_url(host: "localhost", protocol: "http")
        "#{protocol}://#{host}#{RouteHelpers.root_path}"
      end
    end
  end
end
