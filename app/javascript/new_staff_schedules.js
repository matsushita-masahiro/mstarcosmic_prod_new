// スタッフスケジュール関連のJavaScript

let staffSchedulesInitialized = false;

function initializeStaffSchedules() {
  try {
    // console.log('Staff schedules.js loaded - initialization started');

    // より厳密なスタッフスケジュールページ判定
    const staffScheduleContainer = document.querySelector('.staff-schedule-container');
    const currentPath = window.location.pathname;
    
    // スタッフスケジュールページでない場合はスキップ
    if (!staffScheduleContainer || !currentPath.includes('/new_staff_schedules')) {
      // console.log('Not staff schedules page, skipping initialization');
      return;
    }

    // 既に初期化済みの場合はスキップ
    if (staffSchedulesInitialized) {
      // console.log('Staff schedules already initialized, skipping...');
      return;
    }
  } catch (error) {
    // console.error('Staff schedules initialization error:', error);
    return;
  }

  // console.log('Staff schedule page detected, initializing...');
  staffSchedulesInitialized = true;
}

// DOMContentLoadedとturbo:loadの両方のイベントに対応
document.addEventListener('DOMContentLoaded', initializeStaffSchedules);
document.addEventListener('turbo:load', initializeStaffSchedules);

// Turboでページを離れる時のクリーンアップ
document.addEventListener('turbo:before-cache', function() {
  // console.log('Staff schedules page cleanup');
  staffSchedulesInitialized = false;
});

// グローバル関数（HTMLから呼び出される）
if (!window.changeStaff) {
  window.changeStaff = function(staffId) {
    const hiddenDateInput = document.querySelector('input[name="date"]');
    const currentDate = hiddenDateInput ? hiddenDateInput.value : new Date().toISOString().split('T')[0];
    window.location.href = `/new_staff_schedules?staff_id=${staffId}&date=${currentDate}`;
  };
}

if (!window.toggleDayAll) {
  window.toggleDayAll = function(date, checked) {
    const checkboxes = document.querySelectorAll(`input[data-date="${date}"]`);
    checkboxes.forEach(checkbox => {
      checkbox.checked = checked;
    });
  };
}