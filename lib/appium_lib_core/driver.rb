require 'uri'

module Appium
  module Core
    class Driver
      include Waitable
      # Selenium webdriver capabilities
      # @return [Core::Base::Capabilities]
      attr_reader :caps

      # Return http client called in start_driver()
      # @return [Appium::Core::Base::Http::Default] the http client
      attr_reader :http_client

      # Device type to request from the appium server
      # @return [Symbol] :android and :ios, for example
      attr_reader :device

      # Automation name sent to appium server or received from server
      # If automation_name is nil, it is not set both client side and server side.
      # @return [Hash]
      attr_reader :automation_name

      # Custom URL for the selenium server. If set this attribute, ruby_lib_core try to handshake to the custom url.
      # False is by default and then "http://127.0.0.1:#{port}/wd/hub" is used.
      # @return [String]
      attr_reader :custom_url

      # Export session id to textfile in /tmp for 3rd party tools. False bu default.
      # @return [Boolean]
      attr_reader :export_session
      # @return [String] By default, session id is exported in '/tmp/appium_lib_session'
      attr_reader :export_session_path

      # Default wait time for elements to appear
      # Returns the default client side wait. 20 seconds is by default.
      # Provide Appium::Drive like { appium_lib: { wait: 30 } }
      # @return [Integer]
      attr_reader :default_wait

      # Appium's server port. 4723 is by default.
      # Provide Appium::Drive like { appium_lib: { port: 8080 } }
      # @return [Integer]
      attr_reader :port
      DEFAULT_APPIUM_PORT = 4723

      # Return a time wait timeout. 30 seconds is by default.
      # Wait time for ::Appium::Core::Base::Wait, wait and wait_true
      # Provide Appium::Drive like { appium_lib: { wait_timeout: 20 } }
      # @return [Integer]
      attr_reader :wait_timeout

      # Return a time to wait interval. 0.5 seconds is by default.
      # Wait interval time for ::Appium::Core::Base::Wait, wait and wait_true
      # Provide Appium::Drive like { appium_lib: { wait_interval: 0.1 } }
      # @return [Integer]
      attr_reader :wait_interval

      # instance of AbstractEventListener for logging support
      # Nil by default
      attr_reader :listener

      # @return [Appium::Core::Base::Driver]
      attr_reader :driver

      # Creates a new global driver and extend particular methods to `target`
      # @param [Class] target Extend particular methods to this target.
      # @param [Hash] opts A options include capabilities for the Appium Server and for the client.
      # @return [Driver]
      #
      # @example
      #
      #     require 'rubygems'
      #     require 'appium_lib_core'
      #
      #     # Start iOS driver
      #     opts = {
      #              caps: {
      #                platformName: :ios,
      #                platformVersion: '11.0',
      #                deviceName: 'iPhone Simulator',
      #                automationName: 'XCUITest',
      #                app: '/path/to/MyiOS.app'
      #              },
      #              appium_lib: {
      #                server_url: "http://custom-host:8080/wd/hub.com",
      #                export_session: false,
      #                port: 8080,
      #                wait: 0,
      #                wait_timeout: 20,
      #                wait_interval: 0.3,
      #                listener: nil,
      #              }
      #            }
      #     @core = Appium::Core.for(self, opts) # create a core driver with `opts` and extend methods into `self`
      #     @core.start_driver(server_url: server_url) # start driver
      #
      #     # Start iOS driver with .zip file over HTTP
      #     opts = {
      #              caps: {
      #                platformName: :ios,
      #                platformVersion: '11.0',
      #                deviceName: 'iPhone Simulator',
      #                automationName: 'XCUITest',
      #                app: 'http://example.com/path/to/MyiOS.app.zip'
      #              },
      #              appium_lib: {
      #                server_url: "http://custom-host:8080/wd/hub.com",
      #                export_session: false,
      #                port: 8080,
      #                wait: 0,
      #                wait_timeout: 20,
      #                wait_interval: 0.3,
      #                listener: nil,
      #              }
      #            }
      #     @core = Appium::Core.for(self, opts)
      #     @core.start_driver(server_url: server_url)
      #
      def self.for(target, opts = {})
        new(target, opts)
      end

      # @private
      # For testing purpose of delegate_from_appium_driver
      private def delegated_target_for_test
        @delegate_target
      end

      # @private
      def initialize(target, opts = {})
        @delegate_target = target # for testing purpose

        opts = Appium.symbolize_keys opts
        validate_keys(opts)

        @caps = get_caps(opts)

        set_appium_lib_specific_values(get_appium_lib_opts(opts))
        set_app_path
        set_appium_device
        set_automation_name

        extend_for(device: @device, automation_name: @automation_name, target: target)

        self # rubocop:disable Lint/Void
      end

      # Creates a new global driver and quits the old one if it exists.
      # You can customise http_client as the following
      #
      # @param [String] server_url Custom server url to send to requests. Default is "http://127.0.0.1:4723/wd/hub".
      # @param http_client_ops [Hash] Options for http client
      # @option http_client_ops [Hash] :http_client Custom HTTP Client
      # @option http_client_ops [Hash] :open_timeout Custom open timeout for http client.
      # @option http_client_ops [Hash] :read_timeout Custom read timeout for http client.
      # @return [Selenium::WebDriver] the new global driver
      #
      # @example
      #
      #     require 'rubygems'
      #     require 'appium_lib_core'
      #
      #     # platformName takes a string or a symbol.
      #
      #     # Start iOS driver
      #     opts = {
      #              caps: {
      #                platformName: :ios,
      #                platformVersion: '11.0',
      #                deviceName: 'iPhone Simulator',
      #                automationName: 'XCUITest',
      #                app: '/path/to/MyiOS.app'
      #              },
      #              appium_lib: {
      #                wait: 20,
      #                wait_timeout: 20,
      #                wait_interval: 0.3,
      #              }
      #            }
      #
      #     @core = Appium::Core.for(self, opts) # create a core driver with `opts` and extend methods into `self`
      #     @driver = @core.start_driver
      #

      def start_driver(server_url: nil,
                       http_client_ops: { http_client: nil, open_timeout: 999_999, read_timeout: 999_999 })
        server_url ||= "http://127.0.0.1:#{@port}/wd/hub"

        create_http_client http_client: http_client_ops.delete(:http_client),
                           open_timeout: http_client_ops.delete(:open_timeout),
                           read_timeout: http_client_ops.delete(:read_timeout)

        begin
          # included https://github.com/SeleniumHQ/selenium/blob/43f8b3f66e7e01124eff6a5805269ee441f65707/rb/lib/selenium/webdriver/remote/driver.rb#L29
          @driver = ::Appium::Core::Base::Driver.new(http_client: @http_client,
                                                     desired_capabilities: @caps,
                                                     url: server_url,
                                                     listener: @listener)

          # export session
          write_session_id(@driver.session_id, @export_session_path) if @export_session
        rescue Errno::ECONNREFUSED
          raise "ERROR: Unable to connect to Appium. Is the server running on #{server_url}?"
        end

        # If "automationName" is set only server side, this method set "automationName" attribute into @automation_name.
        # Since @automation_name is set only client side before start_driver is called.
        set_automation_name_if_nil

        set_implicit_wait_by_default(@default_wait)

        @driver
      end

      private

      def create_http_client(http_client: nil, open_timeout: nil, read_timeout: nil)
        @http_client ||= http_client ? http_client : Appium::Core::Base::Http::Default.new

        # open_timeout and read_timeout are explicit wait.
        @http_client.open_timeout = open_timeout if open_timeout
        @http_client.read_timeout = read_timeout if read_timeout
      end

      # Ignore setting default wait if the target driver has no implementation
      def set_implicit_wait_by_default(wait)
        @driver.manage.timeouts.implicit_wait = wait
      rescue ::Selenium::WebDriver::Error::UnknownError => e
        unless e.message.include?('The operation requested is not yet implemented')
          raise e.message, ::Appium::Core::Error::ServerError
        end

        Appium::Logger.debug(e.message)
        {}
      rescue ::Selenium::WebDriver::Error::WebDriverError => e
        # FIXME: Temporary rescue until Appium support W3C's implicit wait
        # https://github.com/jlipps/simple-wd-spec#set-timeouts
        unless e.message.include?('Parameters were incorrect. We wanted {"required":["type","ms"]} and you sent ["implicit"]')
          raise e.message, ::Appium::Core::Error::ServerError
        end

        Appium::Logger.debug(e.message)
        {}
      end

      public

      # Quits the driver
      # @return [void]
      #
      # @example
      #
      #   @core.quit_driver
      #
      def quit_driver
        @driver.quit
      rescue # rubocop:disable Lint/RescueWithoutErrorClass
        nil
      end

      # Returns the server's version info
      # @return [Hash]
      #
      # @example
      #
      #   @core.appium_server_version
      #     {
      #         "build" => {
      #             "version" => "0.18.1",
      #             "revision" => "d242ebcfd92046a974347ccc3a28f0e898595198"
      #         }
      #     }
      #
      # Returns blank hash for Selenium Grid since `remote_status` gets 500 error
      #
      # @example
      #
      #   @core.appium_server_version #=> {}
      #
      def appium_server_version
        @driver.remote_status
      rescue Selenium::WebDriver::Error::ServerError => e
        raise ::Appium::Core::Error::ServerError unless e.message.include?('status code 500')
        # driver.remote_status returns 500 error for using selenium grid
        {}
      end

      # Return the platform version as an array of integers
      # @return [Array<Integer>]
      #
      # @example
      #
      #     @core.platform_version #=> [10,1,1]
      #
      def platform_version
        p_version = @driver.capabilities['platformVersion']
        p_version.split('.').map(&:to_i)
      end

      # Takes a png screenshot and saves to the target path.
      #
      # @param png_save_path [String] the full path to save the png
      # @return [File]
      #
      # @example
      #
      #   @core.screenshot '/tmp/hi.png' #=> nil
      #   # same as `@driver.save_screenshot png_save_path`
      #
      def screenshot(png_save_path)
        warn '[DEPRECATION] screenshot will be removed. Please use driver.save_screenshot instead.'
        @driver.save_screenshot png_save_path
      end

      private

      # @private
      def extend_for(device:, automation_name:, target:)
        target.extend Appium::Core
        target.extend Appium::Core::Device

        case device
        when :android
          case automation_name
          when :espresso
            ::Appium::Core::Android::Espresso::Bridge.for(self)
          when :uiautomator2
            ::Appium::Core::Android::Uiautomator2::Bridge.for(self)
          else # default and UiAutomator
            ::Appium::Core::Android::Uiautomator1::Bridge.for(self)
          end
        when :ios
          case automation_name
          when :xcuitest
            ::Appium::Core::Ios::Xcuitest::Bridge.for(self)
          else # default and UIAutomation
            ::Appium::Core::Ios::Uiautomation::Bridge.for(self)
          end
        when :mac
          # no Mac specific extentions
          Appium::Logger.debug('mac')
        when :windows
          # no windows specific extentions
          Appium::Logger.debug('windows')
        when :tizen
          # no tizen specific extentions
          Appium::Logger.debug('tizen')
        else
          Appium::Logger.warn('no device matched')
        end

        target
      end

      # @private
      def validate_keys(opts)
        flatten_ops = flatten_hash_keys(opts)

        raise Error::NoCapabilityError unless opts.member?(:caps)
        if !opts.member?(:appium_lib) && flatten_ops.member?(:appium_lib)
          raise Error::CapabilityStructureError, 'Please check the value of appium_lib in the capability'
        end

        true
      end

      # @private
      def flatten_hash_keys(hash, flatten_keys_result = [])
        hash.each do |key, value|
          flatten_keys_result << key
          flatten_hash_keys(value, flatten_keys_result) if value.is_a?(Hash)
        end

        flatten_keys_result
      end

      # @private
      def get_caps(opts)
        Core::Base::Capabilities.create_capabilities(opts[:caps] || {})
      end

      # @private
      def get_appium_lib_opts(opts)
        opts[:appium_lib] || {}
      end

      # @private
      # Path to the .apk, .app or .app.zip.
      # The path can be local, HTTP/S, Windows Share and other path like `sauce-storage:`.
      # Use @caps[:app] without modifications if the path isn't HTTP/S or local path.
      def set_app_path
        return unless @caps && @caps[:app] && !@caps[:app].empty?
        return if @caps[:app] =~ URI::DEFAULT_PARSER.make_regexp

        app_path = File.expand_path(@caps[:app])
        @caps[:app] = if File.exist? app_path
                        app_path
                      else
                        ::Appium::Logger.info("Use #{@caps[:app]} directly")
                        @caps[:app]
                      end
      end

      # @private
      def set_appium_lib_specific_values(appium_lib_opts)
        @custom_url = appium_lib_opts.fetch :server_url, false
        @default_wait = appium_lib_opts.fetch :wait, 20

        # bump current session id into a particular file
        @export_session = appium_lib_opts.fetch :export_session, false
        @export_session_path = appium_lib_opts.fetch :export_session_path, '/tmp/appium_lib_session'

        @port = appium_lib_opts.fetch :port, DEFAULT_APPIUM_PORT

        # timeout and interval used in ::Appium::Comm.wait/wait_true
        @wait_timeout  = appium_lib_opts.fetch :wait_timeout, ::Appium::Core::Wait::DEFAULT_TIMEOUT
        @wait_interval = appium_lib_opts.fetch :wait_interval, ::Appium::Core::Wait::DEFAULT_INTERVAL

        # to pass it in Selenium.new.
        # `listener = opts.delete(:listener)` is called in Selenium::Driver.new
        @listener = appium_lib_opts.fetch :listener, nil
      end

      # @private
      def set_appium_device
        # https://code.google.com/p/selenium/source/browse/spec-draft.md?repo=mobile
        @device = @caps[:platformName]
        return @device unless @device

        @device = @device.is_a?(Symbol) ? @device : @device.downcase.strip.intern
      end

      # @private
      def set_automation_name
        @automation_name = @caps[:automationName] if @caps[:automationName]
        @automation_name = if @automation_name
                             @automation_name.is_a?(Symbol) ? @automation_name : @automation_name.downcase.strip.intern
                           end
      end

      # @private
      def set_automation_name_if_nil
        return unless @automation_name.nil?
        @automation_name = if @driver.capabilities['automationName']
                             @driver.capabilities['automationName'].downcase.strip.intern
                           end
      end

      # @private
      def write_session_id(session_id, export_path = '/tmp/appium_lib_session')
        File.write(export_path, session_id)
      rescue IOError => e
        ::Appium::Logger.warn e
        nil
      end
    end # class Driver
  end # module Core
end # module Appium
