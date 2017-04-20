module Datadog
  module Contrib
    module Grape
      SERVICE = 'grape'.freeze

      module Patcher
        @patched = false
        module_function

        def patch
          if !@patched && defined?(::Grape)
            begin
              # do not require these by default, but only when actually patching
              require 'ddtrace'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/contrib/grape/endpoint'

              @patched = true
              # patch all endpoints
              patch_endpoint_run()
              patch_endpoint_render()

              # attach a PIN object globally and set the service once
              pin = Datadog::Pin.new(SERVICE, app: 'grape', app_type: Datadog::Ext::AppTypes::WEB)
              pin.onto(::Grape)
              if pin.tracer && pin.service
                pin.tracer.set_service_info(pin.service, pin.app, pin.app_type)
              end

              # subscribe to ActiveSupport events
              Datadog::Contrib::Grape::Endpoint.subscribe()
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Grape integration: #{e}")
            end
          end
          @patched
        end

        def unpatch
          # TODO: implement this (revert aliasing)
          # @patched = false
        end

        def patch_endpoint_run
          ::Grape::Endpoint.class_eval do
            alias_method :run_without_datadog, :run
            def run(*args)
              ::ActiveSupport::Notifications.instrument('endpoint_run.grape.start_process')
              run_without_datadog(*args)
            end
          end
        end

        def patch_endpoint_render
          ::Grape::Endpoint.class_eval do
            class << self
              alias_method :generate_api_method_without_datadog, :generate_api_method
              def generate_api_method(*args, &block)
                method_api = generate_api_method_without_datadog(*args, &block)
                proc do |*args|
                  ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
                  method_api.call(*args)
                end
              end
            end
          end
        end
      end
    end
  end
end
