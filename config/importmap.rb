# Pin npm packages by running ./bin/importmap
pin "jquery", to: "https://code.jquery.com/jquery-3.7.1.min.js", preload: true


pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# config/importmap.rb にこれがあるか確認

pin "fetch_patch", to: "fetch_patch.js"
pin "modal"
pin "fadein"
pin "price_banner"
pin "scroll_top"
pin "zipcodeAPI"
pin "all_schedule_check"
pin "tooltip"
pin "recaptcha_reload", to: "recaptcha_reload.js"
pin "calendar", to: "calendar.js"
pin "new_staff_schedules", to: "new_staff_schedules.js"
pin "business_trips", to: "business_trips.js"






pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
