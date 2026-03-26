// 出張登録関連のJavaScript

let businessTripsInitialized = false;

function initializeBusinessTrips() {
    try {
        // console.log('Business trips.js loaded - initialization started');

        // より厳密な出張登録ページ判定
        const businessTripContainer = document.querySelector('.business-trip-container');
        const currentPath = window.location.pathname;
        
        // 出張登録ページでない場合はスキップ
        if (!businessTripContainer || !currentPath.includes('/business_trips')) {
            // console.log('Not business trips page, skipping initialization');
            return;
        }

        // 既に初期化済みの場合はスキップ
        if (businessTripsInitialized) {
            // console.log('Business trips already initialized, skipping...');
            return;
        }
    } catch (error) {
        // console.error('Business trips initialization error:', error);
        return;
    }

    // console.log('Business trip page detected, initializing...');
    businessTripsInitialized = true;
}

// DOMContentLoadedとturbo:loadの両方のイベントに対応
document.addEventListener('DOMContentLoaded', initializeBusinessTrips);
document.addEventListener('turbo:load', initializeBusinessTrips);

// Turboでページを離れる時のクリーンアップ
document.addEventListener('turbo:before-cache', function () {
    // console.log('Business trips page cleanup');
    businessTripsInitialized = false;
});

// グローバル関数（HTMLから呼び出される）
if (!window.changeMachine) {
    window.changeMachine = function (machineId) {
        const hiddenDateInput = document.querySelector('input[name="date"]');
        const currentDate = hiddenDateInput ? hiddenDateInput.value : new Date().toISOString().split('T')[0];
        window.location.href = `/business_trips?machine_id=${machineId}&date=${currentDate}`;
    };
}

if (!window.toggleDayAll) {
    window.toggleDayAll = function (date, checked) {
        const checkboxes = document.querySelectorAll(`input[data-date="${date}"]`);
        checkboxes.forEach(checkbox => {
            checkbox.checked = checked;
        });
    };
}