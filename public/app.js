document.addEventListener('DOMContentLoaded', () => {
    const wifiList = document.getElementById('wifi-list');
    const loadingState = document.getElementById('loading-state');
    const errorState = document.getElementById('error-state');
    const errorMsg = document.getElementById('error-msg');
    const refreshBtn = document.getElementById('refresh-btn');
    const retryBtn = document.getElementById('retry-btn');
    
    // Modal Elements
    const modal = document.getElementById('password-modal');
    const modalSsidName = document.getElementById('modal-ssid-name');
    const passwordInput = document.getElementById('wifi-password');
    const togglePasswordBtn = document.getElementById('toggle-password');
    const cancelBtn = document.getElementById('cancel-btn');
    const connectForm = document.getElementById('connect-form');
    const connectBtn = document.getElementById('connect-btn');
    const statusMsg = document.getElementById('connection-status');

    let currentSsid = '';

    // Load WiFi Networks
    const fetchNetworks = async () => {
        wifiList.classList.add('hidden');
        errorState.classList.add('hidden');
        loadingState.classList.remove('hidden');
        wifiList.innerHTML = '';

        try {
            const response = await fetch('/api/wifi/scan');
            if (!response.ok) throw new Error('网络请求失败');
            
            const data = await response.json();
            
            if (data.networks && data.networks.length > 0) {
                renderNetworks(data.networks);
                loadingState.classList.add('hidden');
                wifiList.classList.remove('hidden');
            } else {
                showError('未找到网络。请尝试刷新。');
            }
        } catch (err) {
            showError(err.message || '扫描时发生错误。');
        }
    };

    const renderNetworks = (networks) => {
        // Sort by signal strength descending
        networks.sort((a, b) => b.signal - a.signal);

        networks.forEach(network => {
            const li = document.createElement('li');
            li.className = 'wifi-item';
            
            // Generate WiFi Icon based on signal
            let signalBars = 3;
            if (network.signal > 75) signalBars = 3;
            else if (network.signal > 40) signalBars = 2;
            else signalBars = 1;

            li.innerHTML = `
                <div class="wifi-info">
                    <span class="wifi-name">${network.ssid}</span>
                    <span class="wifi-security">${network.security === '--' || network.security === 'None' || network.security === '' ? '开放' : network.security}</span>
                </div>
                <div class="wifi-signal">
                    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        ${signalBars >= 1 ? '<path d="M5 12.55a11 11 0 0 1 14.08 0"></path>' : ''}
                        ${signalBars >= 2 ? '<path d="M1.42 9a16 16 0 0 1 21.16 0"></path>' : ''}
                        ${signalBars >= 3 ? '<path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path>' : ''}
                        <line x1="12" y1="20" x2="12.01" y2="20"></line>
                    </svg>
                </div>
            `;

            li.addEventListener('click', () => openModal(network.ssid));
            wifiList.appendChild(li);
        });
    };

    const showError = (message) => {
        loadingState.classList.add('hidden');
        errorMsg.textContent = message;
        errorState.classList.remove('hidden');
    };

    // Modal Actions
    const openModal = (ssid) => {
        currentSsid = ssid;
        modalSsidName.textContent = ssid;
        passwordInput.value = '';
        statusMsg.classList.add('hidden');
        statusMsg.className = 'status-msg hidden';
        modal.classList.remove('hidden');
        setTimeout(() => passwordInput.focus(), 100);
    };

    const closeModal = () => {
        modal.classList.add('hidden');
        currentSsid = '';
    };

    // Form Submission (Connect)
    connectForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const password = passwordInput.value;
        
        // UI updates
        connectBtn.disabled = true;
        connectBtn.innerHTML = '<span class="spinner" style="width:16px;height:16px;border-width:2px;display:inline-block;vertical-align:middle;margin-right:8px;"></span> 连接中...';
        statusMsg.classList.add('hidden');

        try {
            const response = await fetch('/api/wifi/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ ssid: currentSsid, password })
            });
            
            const result = await response.json();
            
            statusMsg.classList.remove('hidden');
            if (response.ok && result.success) {
                statusMsg.textContent = '连接成功！';
                statusMsg.className = 'status-msg success';
                setTimeout(() => {
                    closeModal();
                    connectBtn.disabled = false;
                    connectBtn.textContent = '连接';
                }, 2000);
            } else {
                throw new Error(result.error || '连接失败');
            }
        } catch (err) {
            statusMsg.classList.remove('hidden');
            statusMsg.textContent = err.message;
            statusMsg.className = 'status-msg error';
            connectBtn.disabled = false;
            connectBtn.textContent = '连接';
        }
    });

    // Event Listeners
    refreshBtn.addEventListener('click', () => {
        refreshBtn.style.transform = 'rotate(180deg)';
        setTimeout(() => refreshBtn.style.transform = '', 300);
        fetchNetworks();
    });
    
    retryBtn.addEventListener('click', fetchNetworks);
    cancelBtn.addEventListener('click', closeModal);
    
    modal.addEventListener('click', (e) => {
        if (e.target === modal) closeModal();
    });

    togglePasswordBtn.addEventListener('click', () => {
        const type = passwordInput.getAttribute('type') === 'password' ? 'text' : 'password';
        passwordInput.setAttribute('type', type);
        // Update icon visually
        if (type === 'text') {
            togglePasswordBtn.innerHTML = `
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
                    <line x1="1" y1="1" x2="23" y2="23"></line>
                </svg>`;
        } else {
            togglePasswordBtn.innerHTML = `
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
                    <circle cx="12" cy="12" r="3"></circle>
                </svg>`;
        }
    });

    // Initial fetch
    fetchNetworks();
});
