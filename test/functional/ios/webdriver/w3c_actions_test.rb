require 'test_helper'

# $ rake test:func:ios TEST=test/functional/ios/webdriver/w3c_actions_test.rb
# rubocop:disable Style/ClassVars
class AppiumLibCoreTest
  module WebDriver
    class W3CActionsTest < AppiumLibCoreTest::Function::TestCase
      def setup
        @@core ||= ::Appium::Core.for(self, Caps::IOS_OPS)
        @@driver ||= @@core.start_driver
      end

      def teardown
        save_reports(@@driver)
      end

      def test_tap
        skip if @@driver.dialect == :oss

        el = @@core.wait { @@driver.find_element(:accessibility_id, 'Buttons') }
        @@driver.action.click(el).perform

        el = @@core.wait { @@driver.find_element(:name, 'Button with Image') }
        rect = el.rect
        @@driver.action.click_and_hold(el).move_to_location(rect.x, rect.y + 500).release.perform
      end
    end
  end
end
