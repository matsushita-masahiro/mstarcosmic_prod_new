// カレンダー関連のJavaScript

let calendarInitialized = false;

// 初期化処理
function initializeCalendar() {
    try {
        // console.log('Calendar.js loaded - initialization started');

        const currentPath = window.location.pathname;
        // console.log('Current path:', currentPath);

        // カレンダーページ判定
        const isCalendarPage = currentPath.includes('/calendar');

        if (!isCalendarPage) {
            // console.log('Not calendar page, skipping calendar initialization');
            return;
        }

        // console.log('Calendar page detected, checking elements...');

        // 既に初期化済みの場合はスキップ
        if (calendarInitialized) {
            // console.log('Calendar already initialized, skipping...');
            return;
        }

        // DOM要素の確認
        const calendarContainer = document.querySelector('.container-wrapper');
        const reserveModal = document.getElementById('reserveModal');

        console.log('Element check:', {
            calendarContainer: !!calendarContainer,
            reserveModal: !!reserveModal
        });

        if (!calendarContainer || !reserveModal) {
            // console.log('Required elements not found, skipping initialization');
            return;
        }

        // console.log('All elements found, proceeding with initialization...');

        const modal = document.getElementById('reserveModal');
        const closeBtn = document.querySelector('.close');
        const cancelBtn = document.querySelector('.modal-cancel');
        const reserveButtons = document.querySelectorAll('.reserve-modal-btn');

        function handleReserveClick() {
            const date = this.getAttribute('data-date');
            const timeSlot = this.getAttribute('data-time-slot');
            const timeDisplay = this.getAttribute('data-time-display');

            console.log('Reserve button clicked:', { date, timeSlot, timeDisplay });

            const modalDate = document.getElementById('modal-date');
            const modalTime = document.getElementById('modal-time');
            const formDate = document.getElementById('form-date');
            const formTimeSlot = document.getElementById('form-time-slot');

            if (modalDate) modalDate.textContent = new Date(date).toLocaleDateString('ja-JP');
            if (modalTime) modalTime.textContent = timeDisplay;
            if (formDate) formDate.value = date;
            if (formTimeSlot) formTimeSlot.value = timeSlot;

            fetchAvailableStaff(date, timeSlot);

            modal.style.display = 'block';
            setTimeout(() => modal.classList.add('show'), 10);
            document.body.style.overflow = 'hidden';
        }

        reserveButtons.forEach(button => {
            button.removeEventListener('click', handleReserveClick);
            button.addEventListener('click', handleReserveClick);
        });

        function closeModal() {
            modal.classList.remove('show');
            setTimeout(() => modal.style.display = 'none', 300);
            document.body.style.overflow = 'auto';
            const reserveForm = document.getElementById('reserve-form');
            if (reserveForm) reserveForm.reset();
        }

        if (closeBtn) closeBtn.addEventListener('click', closeModal);
        if (cancelBtn) cancelBtn.addEventListener('click', closeModal);

        window.addEventListener('click', event => {
            if (event.target === modal) closeModal();
        });

        function fetchAvailableStaff(date, timeSlot) {
            console.log('Fetching available staff for:', { date, timeSlot });

            fetch(`/calendar/availability?date=${date}&time_slot=${timeSlot}`, {
                method: 'GET',
                headers: {
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest'
                }
            })
                .then(response => {
                    console.log('Response status:', response.status);
                    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                    return response.json();
                })
                .then(data => {
                    console.log('Staff data received:', data);
                    const staffSelect = document.getElementById('staff-select');
                    if (!staffSelect) return console.error('Staff select element not found');

                    staffSelect.innerHTML = '<option value="">スタッフを選択してください</option>';

                    if (data.staff_list && data.staff_list.length > 0) {
                        data.staff_list.forEach(staff => {
                            const option = document.createElement('option');
                            option.value = staff.id;
                            option.textContent = staff.name;
                            staffSelect.appendChild(option);
                        });
                    } else {
                        const option = document.createElement('option');
                        option.value = '';
                        option.textContent = '利用可能なスタッフがいません';
                        option.disabled = true;
                        staffSelect.appendChild(option);
                    }
                })
                .catch(error => {
                    console.error('Error fetching staff:', error);
                    const staffSelect = document.getElementById('staff-select');
                    if (staffSelect) {
                        staffSelect.innerHTML = '<option value="">エラーが発生しました</option>';
                    }
                });
        }

        const reserveForm = document.getElementById('reserve-form');
        if (reserveForm) {
            reserveForm.addEventListener('submit', function (e) {
                console.log('Form submission started');
                const date = document.getElementById('form-date')?.value;
                const timeSlot = document.getElementById('form-time-slot')?.value;
                const staffId = document.getElementById('staff-select')?.value;
                const durationElement = document.getElementById('duration-select');
                const duration = durationElement?.value;

                const staffElement = document.getElementById('staff-select');
                console.log('Staff element found:', !!staffElement);
                console.log('Staff element value:', staffElement?.value);
                console.log('Staff element selected index:', staffElement?.selectedIndex);
                console.log('Duration element found:', !!durationElement);
                console.log('Duration element value:', duration);
                console.log('Form validation:', { date, timeSlot, staffId, duration });

                if (!date || !timeSlot || !staffId || !duration) {
                    console.error('Missing required fields');
                    alert('必須項目が入力されていません。');
                    e.preventDefault();
                }
            });
        }

        initAdminTooltips();

        const mobileMenuToggle = document.getElementById('mobileMenuToggle');
        const headerActions = document.getElementById('headerActions');
        if (mobileMenuToggle && headerActions) {
            mobileMenuToggle.addEventListener('click', function () {
                this.classList.toggle('active');
                headerActions.classList.toggle('active');
            });
        }

        calendarInitialized = true;
        console.log('Calendar initialization completed');

    } catch (error) {
        console.error('Calendar initialization error:', error);
    }
}

function ensureCalendarInitialization() {
    const currentPath = window.location.pathname;
    if (currentPath !== '/calendar') return;
    if (calendarInitialized) return;

    const calendarContainer = document.querySelector('.container-wrapper');
    const reserveModal = document.getElementById('reserveModal');

    if (calendarContainer && reserveModal) {
        console.log('Elements found, initializing calendar...');
        initializeCalendar();
    } else {
        console.log('Elements not found, retrying in 300ms...');
        setTimeout(ensureCalendarInitialization, 300);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    setTimeout(ensureCalendarInitialization, 100);
});

document.addEventListener('turbo:load', () => {
    setTimeout(ensureCalendarInitialization, 100);
});

window.addEventListener('load', () => {
    setTimeout(ensureCalendarInitialization, 200);
});

let retryCount = 0;
const maxRetries = 10;

function retryInitialization() {
    if (retryCount >= maxRetries || calendarInitialized) return;
    if (window.location.pathname !== '/calendar') return;

    retryCount++;
    console.log(`Retry initialization attempt ${retryCount}/${maxRetries}`);

    const calendarContainer = document.querySelector('.container-wrapper');
    const reserveModal = document.getElementById('reserveModal');

    if (calendarContainer && reserveModal) {
        console.log('Retry found elements, initializing...');
        initializeCalendar();
    } else {
        const delay = Math.min(500 * retryCount, 3000);
        setTimeout(retryInitialization, delay);
    }
}

setTimeout(retryInitialization, 1000);

window.forceCalendarInit = function () {
    console.log('Manual calendar initialization triggered...');
    calendarInitialized = false;
    retryCount = 0;
    initializeCalendar();
};

document.addEventListener('turbo:before-cache', function () {
    try {
        const modal = document.getElementById('reserveModal');
        if (modal) {
            modal.style.display = 'none';
            modal.classList.remove('show');
        }
        document.body.style.overflow = 'auto';
        calendarInitialized = false;
        retryCount = 0;
        console.log('Calendar cleanup completed');
    } catch (error) {
        console.log('Calendar cleanup error (ignored):', error.message);
        calendarInitialized = false;
    }
});

function initAdminTooltips() {
    const adminTooltips = document.querySelectorAll('.admin-tooltip');
    console.log('Admin tooltips found:', adminTooltips.length);

    if (adminTooltips.length === 0) return;

    let currentTooltip = null;

    adminTooltips.forEach(element => {
        element.addEventListener('mouseenter', function (e) {
            try {
                const reservesData = this.dataset.reserves;
                if (reservesData) {
                    const parsedData = JSON.parse(reservesData);
                    if (parsedData && parsedData.length > 0) {
                        showTooltip(e, parsedData);
                    }
                }
            } catch (error) {
                console.error('Error processing reserves data:', error);
            }
        });

        element.addEventListener('mouseleave', hideTooltip);
        element.addEventListener('mousemove', updateTooltipPosition);
    });

    function showTooltip(event, reservesData) {
        hideTooltip();

        let tooltipContent = '';
        reservesData.forEach((reserve, index) => {
            if (index > 0) tooltipContent += '<hr class="tooltip-divider">';
            tooltipContent += `
        <div class="tooltip-reserve">
          <div class="tooltip-row"><span class="tooltip-label">予約者:</span><span class="tooltip-value">${reserve.customer_name}</span></div>
          <div class="tooltip-row"><span class="tooltip-label">電話:</span><span class="tooltip-value">${reserve.customer_tel}</span></div>
          <div class="tooltip-row"><span class="tooltip-label">スタッフ:</span><span class="tooltip-value">${reserve.staff_name}</span></div>
          <div class="tooltip-row"><span class="tooltip-label">時間:</span><span class="tooltip-value">${reserve.start_time}〜 (${reserve.duration})</span></div>
          <div class="tooltip-row"><span class="tooltip-label">会員:</span><span class="tooltip-value ${reserve.is_member ? 'member' : 'non-member'}">${reserve.member_type}</span></div>
        </div>
      `;
        });

        const tooltip = document.createElement('div');
        tooltip.className = 'admin-tooltip-popup';
        tooltip.innerHTML = tooltipContent;
        document.body.appendChild(tooltip);
        currentTooltip = tooltip;

        updateTooltipPosition(event);
    }

    function updateTooltipPosition(event) {
        if (!currentTooltip) return;

        const tooltipRect = currentTooltip.getBoundingClientRect();
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;

        let left = event.clientX + 10;
        let top = event.clientY + 10;

        if (left + tooltipRect.width > viewportWidth) {
            left = event.clientX - tooltipRect.width - 10;
        }
        if (top + tooltipRect.height > viewportHeight) {
            top = event.clientY - tooltipRect.height - 10;
        }

        currentTooltip.style.left = `${left}px`;
        currentTooltip.style.top = `${top}px`;
    }

    function hideTooltip() {
        if (currentTooltip) {
            currentTooltip.remove();
            currentTooltip = null;
        }
    }
}