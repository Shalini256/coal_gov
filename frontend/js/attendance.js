/**
 * attendance.js — Attendance & Workforce Management with Spoof-Resistant GPS Check-In.
 */
let allMines = [];
let allContractors = [];
let allWorkers = [];
let allAttendance = [];
let allAnomalies = [];

// Anti-Spoofing & Simulation State
let isMockLocationSimulated = false;
let clockSkewMinutes = 0;
let livenessResult = true;
let cameraStream = null;

document.addEventListener('DOMContentLoaded', async () => {
  AUTH.guardPage();
  AUTH.renderShell('attendance.html');

  const user = AUTH.getUser();
  const canManage = ['SUPER_ADMIN', 'MINE_MANAGER', 'SAFETY_OFFICER'].includes(user?.role_key);

  if (canManage) {
    const btnMark = document.getElementById('btn-mark-attendance');
    const btnAddWorker = document.getElementById('btn-add-worker');
    if (btnMark) btnMark.classList.remove('hidden');
    if (btnAddWorker) btnAddWorker.classList.remove('hidden');
  }

  // Set default date to today
  const todayStr = new Date().toISOString().split('T')[0];
  document.getElementById('filter-date').value = todayStr;
  document.getElementById('att-date').value = todayStr;

  // Filter Event Listeners
  document.getElementById('filter-mine').addEventListener('change', applyFilters);
  document.getElementById('filter-contractor').addEventListener('change', applyFilters);
  document.getElementById('filter-date').addEventListener('change', applyFilters);
  document.getElementById('filter-status').addEventListener('change', applyFilters);

  // Standard Mark Attendance Modal
  const btnMark = document.getElementById('btn-mark-attendance');
  if (btnMark) btnMark.addEventListener('click', openMarkModal);
  document.getElementById('mark-modal-close').addEventListener('click', closeMarkModal);
  document.getElementById('mark-modal-cancel').addEventListener('click', closeMarkModal);
  document.getElementById('mark-form').addEventListener('submit', handleMarkSubmit);

  // Register Worker Modal
  const btnAddWorker = document.getElementById('btn-add-worker');
  if (btnAddWorker) btnAddWorker.addEventListener('click', openWorkerModal);
  document.getElementById('worker-modal-close').addEventListener('click', closeWorkerModal);
  document.getElementById('worker-modal-cancel').addEventListener('click', closeWorkerModal);
  document.getElementById('worker-form').addEventListener('submit', handleWorkerSubmit);

  document.getElementById('att-mine').addEventListener('change', (e) => populateWorkersDropdown(e.target.value, 'att-worker'));

  // Self Check-In Modal & Spoof-Resistance
  document.getElementById('btn-self-checkin').addEventListener('click', openSelfCheckinModal);
  document.getElementById('self-checkin-modal-close').addEventListener('click', closeSelfCheckinModal);
  document.getElementById('self-checkin-modal-cancel').addEventListener('click', closeSelfCheckinModal);
  document.getElementById('self-checkin-form').addEventListener('submit', handleSelfCheckinSubmit);

  document.getElementById('self-mine').addEventListener('change', (e) => {
    populateWorkersDropdown(e.target.value, 'self-worker');
    updateDistanceUI();
  });
  document.getElementById('self-lat').addEventListener('input', updateDistanceUI);
  document.getElementById('self-lng').addEventListener('input', updateDistanceUI);
  document.getElementById('btn-acquire-gps').addEventListener('click', acquireDeviceGPS);

  // Simulation Presets
  document.getElementById('sim-inside-geofence').addEventListener('click', simInsideGeofence);
  document.getElementById('sim-outside-geofence').addEventListener('click', simOutsideGeofence);
  document.getElementById('sim-mock-gps').addEventListener('click', simMockGPS);
  document.getElementById('sim-velocity-jump').addEventListener('click', simVelocityJump);
  document.getElementById('sim-clock-skew').addEventListener('click', simClockSkew);
  document.getElementById('sim-cluster-batch').addEventListener('click', simClusterBatch);

  // Liveness Controls
  document.getElementById('toggle-liveness').addEventListener('change', (e) => {
    document.getElementById('liveness-panel').classList.toggle('hidden', !e.target.checked);
  });
  document.getElementById('btn-start-camera').addEventListener('click', startCamera);
  document.getElementById('btn-pass-liveness').addEventListener('click', () => {
    livenessResult = true;
    const prompt = document.getElementById('liveness-prompt');
    prompt.textContent = '✅ Liveness Verified: Blink & head turn gesture passed';
    prompt.style.color = '#10b981';
  });
  document.getElementById('btn-fail-liveness').addEventListener('click', () => {
    livenessResult = false;
    const prompt = document.getElementById('liveness-prompt');
    prompt.textContent = '⚠️ Liveness Warning: Gesture failed (Will log soft anomaly)';
    prompt.style.color = '#ef4444';
  });

  // Refresh Anomalies
  document.getElementById('btn-refresh-anomalies').addEventListener('click', loadAttendanceAnomalies);

  await loadInitialDropdowns();
  await loadAttendance();
  await loadReport();
  await loadAttendanceAnomalies();
});

/* =====================================================================
   Initial Data & Dropdowns
   ===================================================================== */
async function loadInitialDropdowns() {
  try {
    const [mines, contractors] = await Promise.all([
      API.get('/mines'),
      API.get('/contractors').catch(() => [])
    ]);
    allMines = mines || [];
    allContractors = contractors || [];

    // Populate Mine filters & modals
    const mineFilter = document.getElementById('filter-mine');
    const attMine = document.getElementById('att-mine');
    const wMine = document.getElementById('w-mine');
    const selfMine = document.getElementById('self-mine');

    const mineOpts = allMines.map(m => `<option value="${m.id}" data-lat="${m.latitude}" data-lng="${m.longitude}">${m.mine_name} (${m.mine_code})</option>`).join('');
    mineFilter.innerHTML = `<option value="">All Mines</option>${mineOpts}`;
    attMine.innerHTML = mineOpts;
    wMine.innerHTML = mineOpts;
    selfMine.innerHTML = mineOpts;

    // Populate Contractor filters & modals
    const contFilter = document.getElementById('filter-contractor');
    const wCont = document.getElementById('w-contractor');
    const contOpts = allContractors.map(c => `<option value="${c.id}">${c.company_name}</option>`).join('');
    contFilter.innerHTML = `<option value="">All Contractors / Direct</option>${contOpts}`;
    wCont.innerHTML = `<option value="">Direct CIL Employee</option>${contOpts}`;

    if (allMines.length > 0) {
      await populateWorkersDropdown(allMines[0].id, 'att-worker');
      await populateWorkersDropdown(allMines[0].id, 'self-worker');
      // Set default coords for self checkin modal
      if (allMines[0].latitude && allMines[0].longitude) {
        document.getElementById('self-lat').value = (allMines[0].latitude + 0.0002).toFixed(6);
        document.getElementById('self-lng').value = (allMines[0].longitude + 0.0002).toFixed(6);
      }
    }
  } catch (err) {
    console.error('Failed to load initial dropdowns', err);
  }
}

async function populateWorkersDropdown(mineId, targetElementId) {
  try {
    const workers = await API.get(`/workers?mine_id=${mineId}`);
    const selectElem = document.getElementById(targetElementId);
    if (!selectElem) return;

    if (!workers || workers.length === 0) {
      selectElem.innerHTML = `<option value="">No active workers registered</option>`;
    } else {
      selectElem.innerHTML = workers.map(w => `<option value="${w.id}">${w.full_name} (${w.worker_code} - ${w.designation})</option>`).join('');
    }
  } catch (e) {
    console.error('Failed to populate workers', e);
  }
}

/* =====================================================================
   Roster & Reports
   ===================================================================== */
async function loadAttendance() {
  const tbody = document.getElementById('attendance-table-body');
  tbody.innerHTML = `<tr><td colspan="12" class="state-panel">Loading attendance roster...</td></tr>`;

  try {
    const mineId = document.getElementById('filter-mine').value;
    const contId = document.getElementById('filter-contractor').value;
    const date = document.getElementById('filter-date').value;
    const status = document.getElementById('filter-status').value;

    let url = `/attendance?`;
    if (mineId) url += `mine_id=${mineId}&`;
    if (contId) url += `contractor_id=${contId}&`;
    if (date) url += `date=${date}&`;
    if (status) url += `status=${status}&`;

    allAttendance = await API.get(url);
    renderAttendanceTable(allAttendance);
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="12" class="state-panel error">${err.message}</td></tr>`;
  }
}

async function loadReport() {
  try {
    const mineId = document.getElementById('filter-mine').value;
    const contId = document.getElementById('filter-contractor').value;
    let url = `/attendance/report?`;
    if (mineId) url += `mine_id=${mineId}&`;
    if (contId) url += `contractor_id=${contId}&`;

    const report = await API.get(url);
    document.getElementById('kpi-total-workers').textContent = report.total_workers || '0';
    document.getElementById('kpi-present-count').textContent = report.status_breakdown?.PRESENT || '0';
    
    const absentTotal = (report.status_breakdown?.ABSENT || 0) + (report.status_breakdown?.LEAVE || 0);
    document.getElementById('kpi-absent-count').textContent = absentTotal;
    
    const rate = Math.round(report.attendance_rate || 0);
    document.getElementById('kpi-rate').textContent = `${rate}%`;
  } catch (e) {
    console.error('Failed to load attendance report', e);
  }
}

function applyFilters() {
  loadAttendance();
  loadReport();
}

function renderAttendanceTable(records) {
  const tbody = document.getElementById('attendance-table-body');
  if (!records || records.length === 0) {
    tbody.innerHTML = `<tr><td colspan="12" class="state-panel">No attendance records match current filters.</td></tr>`;
    return;
  }

  tbody.innerHTML = records.map(r => {
    let badgeClass = 'badge-active';
    if (r.status === 'ABSENT') badgeClass = 'badge-critical';
    else if (r.status === 'LEAVE') badgeClass = 'badge-info';
    else if (r.status === 'HALF_DAY') badgeClass = 'badge-warning';

    // Verification & Geolocation Tag
    let geoHtml = `<span class="geo-tag manual">📋 Manager Batch</span>`;
    if (r.distance_from_mine_m !== null && r.distance_from_mine_m !== undefined) {
      const dist = Math.round(r.distance_from_mine_m);
      if (r.is_mock_location) {
        geoHtml = `<span class="geo-tag mock">🚫 Mock GPS (${dist}m)</span>`;
      } else if (dist <= 500) {
        geoHtml = `<span class="geo-tag verified">📍 Verified (${dist}m)</span>`;
      } else {
        geoHtml = `<span class="geo-tag breach">⚠️ Out of Bounds (${dist}m)</span>`;
      }
    }

    // Tamper Flag Tag
    let tamperHtml = `<span class="badge" style="background:#f1f5f9; color:#64748b;">Standard</span>`;
    if (r.tamper_flag) {
      tamperHtml = `<span class="badge badge-critical" style="font-weight:600;">🚨 Flagged</span>`;
    } else if (r.distance_from_mine_m !== null && r.distance_from_mine_m !== undefined) {
      tamperHtml = `<span class="badge badge-active">🛡️ Secure</span>`;
    }

    return `
      <tr>
        <td class="mono font-semibold">${r.worker_code || 'AGGREGATE'}</td>
        <td><strong>${r.worker_name || 'Mine-wide Headcount'}</strong></td>
        <td>${r.designation || 'All Shifts'}</td>
        <td>${r.mine_name}</td>
        <td>${r.contractor_name || '<span class="text-muted">CIL Direct</span>'}</td>
        <td><span class="mono">${r.shift || 'GENERAL'}</span></td>
        <td>${r.overtime_hours > 0 ? `<strong>+${r.overtime_hours} hrs</strong>` : '-'}</td>
        <td class="mono">${r.record_date}</td>
        <td><span class="badge ${badgeClass}">${r.status}</span></td>
        <td>${geoHtml}</td>
        <td>${tamperHtml}</td>
        <td>${r.marked_by_name || 'Self Check-In'}</td>
      </tr>
    `;
  }).join('');
}

/* =====================================================================
   Anti-Spoofing & Tamper Audit Log
   ===================================================================== */
async function loadAttendanceAnomalies() {
  const tbody = document.getElementById('anomalies-table-body');
  if (!tbody) return;

  try {
    const res = await API.get('/analytics/anomalies');
    const anomalies = Array.isArray(res) ? res : (res?.data || []);
    
    // Filter attendance and spoofing-related anomalies
    const attAnomalies = anomalies.filter(a => 
      ['MOCK_LOCATION', 'GEOFENCE_BREACH', 'TIME_ANOMALY', 'VELOCITY_ANOMALY', 'SCRIPTED_BATCH', 'LIVENESS_FAILED'].includes(a.anomaly_type) ||
      a.worker_id !== null && a.worker_id !== undefined
    );

    if (attAnomalies.length === 0) {
      tbody.innerHTML = `<tr><td colspan="7" class="state-panel" style="color:var(--color-low);">No tamper anomalies detected. All attendance check-ins are verified and secure.</td></tr>`;
      return;
    }

    tbody.innerHTML = attAnomalies.map(a => {
      let sevClass = 'badge-critical';
      if (a.severity === 'HIGH') sevClass = 'badge-warning';
      else if (a.severity === 'MEDIUM') sevClass = 'badge-info';
      else if (a.severity === 'LOW') sevClass = 'badge-active';

      let timeFormatted = a.detected_at ? new Date(a.detected_at).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }) : '-';

      let vectorLabel = a.anomaly_type;
      if (a.anomaly_type === 'MOCK_LOCATION') vectorLabel = '🚫 Mock GPS Provider';
      else if (a.anomaly_type === 'GEOFENCE_BREACH') vectorLabel = '⚠️ Geofence Perimeter Breach';
      else if (a.anomaly_type === 'VELOCITY_ANOMALY') vectorLabel = '⚡ Velocity Jump (>80 km/h)';
      else if (a.anomaly_type === 'SCRIPTED_BATCH') vectorLabel = '🤖 Scripted Cluster Batch';
      else if (a.anomaly_type === 'TIME_ANOMALY') vectorLabel = '🕒 Clock Skew Tampering';
      else if (a.anomaly_type === 'LIVENESS_FAILED') vectorLabel = '👁️ Liveness Test Mismatch';

      return `
        <tr>
          <td class="mono font-semibold" style="font-size:12px;">${timeFormatted}</td>
          <td><strong>${a.worker_name ? `${a.worker_name} (${a.worker_code})` : `Worker #${a.worker_id || '-'}`}</strong></td>
          <td>${a.mine_name || 'Mine'}</td>
          <td><span class="mono font-semibold" style="font-size:12px;">${vectorLabel}</span></td>
          <td><span class="badge ${sevClass}">${a.severity}</span></td>
          <td style="font-size:12.5px; color:var(--color-ink); max-width:320px;">${a.description}</td>
          <td><span class="badge badge-warning">${a.status}</span></td>
        </tr>
      `;
    }).join('');
  } catch (err) {
    console.error('Failed to load anomalies audit log', err);
    tbody.innerHTML = `<tr><td colspan="7" class="state-panel error">Failed to load audit log: ${err.message}</td></tr>`;
  }
}

/* =====================================================================
   Self Check-In Modal & Anti-Spoofing Actions
   ===================================================================== */
function openSelfCheckinModal() {
  document.getElementById('self-checkin-modal').classList.remove('hidden');
  document.getElementById('self-checkin-alert').classList.add('hidden');
  document.getElementById('self-checkin-success').classList.add('hidden');
  
  // Default mine & workers
  const selMine = document.getElementById('self-mine');
  if (selMine && selMine.value) {
    populateWorkersDropdown(selMine.value, 'self-worker');
    updateDistanceUI();
  }
}

function closeSelfCheckinModal() {
  document.getElementById('self-checkin-modal').classList.add('hidden');
  document.getElementById('self-checkin-alert').classList.add('hidden');
  document.getElementById('self-checkin-success').classList.add('hidden');
  isMockLocationSimulated = false;
  clockSkewMinutes = 0;
  stopCamera();
}

function computeHaversine(lat1, lon1, lat2, lon2) {
  const R = 6371000; // meters
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function updateDistanceUI() {
  const mineId = parseInt(document.getElementById('self-mine').value);
  const lat = parseFloat(document.getElementById('self-lat').value);
  const lng = parseFloat(document.getElementById('self-lng').value);

  const distVal = document.getElementById('dist-calc-value');
  const tag = document.getElementById('geofence-status-tag');
  const box = document.getElementById('distance-indicator-box');

  const mine = allMines.find(m => m.id === mineId);
  if (!mine || isNaN(lat) || isNaN(lng) || !mine.latitude || !mine.longitude) {
    distVal.textContent = '-- m';
    tag.className = 'geo-tag manual';
    tag.textContent = 'Awaiting GPS Coordinates';
    box.className = 'distance-indicator';
    return;
  }

  const distanceM = computeHaversine(lat, lng, mine.latitude, mine.longitude);
  distVal.textContent = `${Math.round(distanceM)} meters`;

  if (distanceM <= 500) {
    tag.className = 'geo-tag verified';
    tag.innerHTML = `✓ Within 500m Geofence (${Math.round(distanceM)}m)`;
    box.className = 'distance-indicator ok';
  } else {
    tag.className = 'geo-tag breach';
    tag.innerHTML = `⚠️ Outside Geofence (${(distanceM / 1000).toFixed(2)}km &gt; 500m)`;
    box.className = 'distance-indicator out-of-bounds';
  }
}

function acquireDeviceGPS() {
  const statusText = document.getElementById('gps-status-text');
  if (!navigator.geolocation) {
    statusText.textContent = 'Geolocation is not supported by your browser';
    return;
  }

  statusText.textContent = 'Acquiring GPS fix...';
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      document.getElementById('self-lat').value = pos.coords.latitude.toFixed(6);
      document.getElementById('self-lng').value = pos.coords.longitude.toFixed(6);
      statusText.textContent = `GPS Acquired (Accuracy: ±${Math.round(pos.coords.accuracy)}m)`;
      isMockLocationSimulated = false;
      clockSkewMinutes = 0;
      updateDistanceUI();
    },
    (err) => {
      statusText.textContent = `GPS Error: ${err.message}`;
    },
    { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
  );
}

/* =====================================================================
   Simulation Presets (For Demonstration / Evaluation)
   ===================================================================== */
function simInsideGeofence() {
  const mineId = parseInt(document.getElementById('self-mine').value);
  const mine = allMines.find(m => m.id === mineId) || allMines[0];
  if (mine && mine.latitude && mine.longitude) {
    document.getElementById('self-lat').value = (mine.latitude + 0.0003).toFixed(6);
    document.getElementById('self-lng').value = (mine.longitude + 0.0003).toFixed(6);
  }
  isMockLocationSimulated = false;
  clockSkewMinutes = 0;
  document.getElementById('gps-status-text').textContent = 'Simulated: Inside 500m Geofence (~45m from mine center)';
  updateDistanceUI();
}

function simOutsideGeofence() {
  const mineId = parseInt(document.getElementById('self-mine').value);
  const mine = allMines.find(m => m.id === mineId) || allMines[0];
  if (mine && mine.latitude && mine.longitude) {
    document.getElementById('self-lat').value = (mine.latitude + 0.025).toFixed(6);
    document.getElementById('self-lng').value = (mine.longitude + 0.025).toFixed(6);
  }
  isMockLocationSimulated = false;
  clockSkewMinutes = 0;
  document.getElementById('gps-status-text').textContent = 'Simulated: Outside Geofence (2.8 km away - Breach Test)';
  updateDistanceUI();
}

function simMockGPS() {
  simInsideGeofence();
  isMockLocationSimulated = true;
  document.getElementById('gps-status-text').innerHTML = '<span style="color:#b45309; font-weight:600;">⚠️ Simulated Mock GPS Provider Active (isFromMockProvider: true)</span>';
}

function simVelocityJump() {
  const mineId = parseInt(document.getElementById('self-mine').value);
  const mine = allMines.find(m => m.id === mineId) || allMines[0];
  if (mine && mine.latitude && mine.longitude) {
    document.getElementById('self-lat').value = (mine.latitude + 1.2).toFixed(6);
    document.getElementById('self-lng').value = (mine.longitude + 1.2).toFixed(6);
  }
  isMockLocationSimulated = false;
  clockSkewMinutes = 0;
  document.getElementById('gps-status-text').textContent = 'Simulated: Teleport Jump (~150km away within minutes)';
  updateDistanceUI();
}

function simClockSkew() {
  simInsideGeofence();
  clockSkewMinutes = -25; // 25 mins in past
  document.getElementById('gps-status-text').textContent = 'Simulated: Client Clock manipulated (-25 min skew)';
}

async function simClusterBatch() {
  const mineId = parseInt(document.getElementById('self-mine').value);
  const mine = allMines.find(m => m.id === mineId) || allMines[0];
  if (!mine) return;

  const lat = (mine.latitude + 0.0001);
  const lng = (mine.longitude + 0.0001);
  document.getElementById('gps-status-text').textContent = 'Firing 5 rapid check-ins in parallel to simulate scripted cluster attack...';

  try {
    const workers = await API.get(`/workers?mine_id=${mineId}`);
    if (workers.length < 5) {
      showToast('Need at least 5 registered workers in mine to demonstrate cluster attack', 'warning');
      return;
    }

    const promises = workers.slice(0, 5).map(w => {
      return API.post('/attendance/self-checkin', {
        mine_id: mineId,
        worker_id: w.id,
        lat: lat,
        lng: lng,
        is_mock_location: false,
        device_uptime_ms: Math.floor(performance.now()),
        client_reported_time: new Date().toISOString(),
        liveness_passed: true
      }).catch(err => ({ error: err.message }));
    });

    await Promise.all(promises);
    showToast('Scripted batch attack sent. Checking audit anomalies...', 'info');
    await loadAttendance();
    await loadAttendanceAnomalies();
    document.getElementById('gps-status-text').textContent = 'Cluster test completed. Check Anti-Spoofing Audit Log below!';
  } catch (err) {
    showError(err);
  }
}

/* =====================================================================
   Tier 2 Facial Liveness & Webcam
   ===================================================================== */
async function startCamera() {
  const video = document.getElementById('liveness-video');
  const btn = document.getElementById('btn-start-camera');
  const prompt = document.getElementById('liveness-prompt');

  try {
    if (cameraStream) {
      stopCamera();
      btn.textContent = 'Start Camera';
      return;
    }

    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 320 }, height: { ideal: 200 } }
    });
    video.srcObject = cameraStream;
    btn.textContent = 'Stop Camera';
    prompt.textContent = '👁️ Camera active: Please blink twice or turn head slightly left';
  } catch (e) {
    console.warn('Webcam not available or access denied:', e);
    prompt.textContent = '⚠️ Webcam access unavailable. You can use simulation buttons to test Tier 2 liveness.';
  }
}

function stopCamera() {
  if (cameraStream) {
    cameraStream.getTracks().forEach(t => t.stop());
    cameraStream = null;
  }
  const video = document.getElementById('liveness-video');
  if (video) video.srcObject = null;
  const btn = document.getElementById('btn-start-camera');
  if (btn) btn.textContent = 'Start Camera';
}

/* =====================================================================
   Handle Self Check-In Form Submit
   ===================================================================== */
async function handleSelfCheckinSubmit(e) {
  e.preventDefault();
  const alertBox = document.getElementById('self-checkin-alert');
  const alertText = document.getElementById('self-checkin-alert-text');
  const successBox = document.getElementById('self-checkin-success');
  const successText = document.getElementById('self-checkin-success-text');

  alertBox.classList.add('hidden');
  successBox.classList.add('hidden');

  const mineId = parseInt(document.getElementById('self-mine').value);
  const workerId = parseInt(document.getElementById('self-worker').value);
  const lat = parseFloat(document.getElementById('self-lat').value);
  const lng = parseFloat(document.getElementById('self-lng').value);
  const toggleLiveness = document.getElementById('toggle-liveness').checked;

  if (isNaN(mineId) || isNaN(workerId)) {
    alertText.textContent = 'Please select a valid Mine Site and Worker.';
    alertBox.classList.remove('hidden');
    return;
  }

  if (isNaN(lat) || isNaN(lng)) {
    alertText.textContent = 'Please provide valid GPS latitude and longitude coordinates.';
    alertBox.classList.remove('hidden');
    return;
  }

  // Calculate client time with any simulated skew
  const clientTime = new Date(Date.now() + clockSkewMinutes * 60000).toISOString();

  const payload = {
    mine_id: mineId,
    worker_id: workerId,
    lat: lat,
    lng: lng,
    is_mock_location: isMockLocationSimulated,
    device_uptime_ms: Math.floor(performance.now()),
    client_reported_time: clientTime,
    liveness_passed: toggleLiveness ? livenessResult : null
  };

  const submitBtn = document.getElementById('self-checkin-submit-btn');
  submitBtn.disabled = true;
  submitBtn.textContent = 'Verifying with Anti-Spoofing Engine...';

  try {
    const res = await API.post('/attendance/self-checkin', payload);
    const data = res?.data || res;

    successText.innerHTML = `
      <strong>Check-In Confirmed!</strong><br />
      Distance to mine center: <strong>${Math.round(data.distance_from_mine_m || 0)}m</strong> (Geofence limit: ${data.geofence_radius_m || 500}m).<br />
      Tamper Flag: <strong>${data.tamper_flag ? 'Flagged for Audit' : 'Secure'}</strong> | Liveness: <strong>${data.liveness_passed ? 'Verified' : 'Bypassed'}</strong>
    `;
    successBox.classList.remove('hidden');
    showToast('Worker check-in verified and recorded successfully', 'success');

    await loadAttendance();
    await loadReport();
    await loadAttendanceAnomalies();

    setTimeout(() => {
      closeSelfCheckinModal();
    }, 2500);
  } catch (err) {
    // 403 Forbidden or 400 Bad Request
    alertText.innerHTML = `
      <strong>Check-In Blocked by Anti-Spoofing Policy:</strong><br />
      ${err.message || 'Verification rejected'}
    `;
    alertBox.classList.remove('hidden');

    // Refresh anomalies table so manager can see the blocked incident immediately
    await loadAttendanceAnomalies();
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = 'Submit Verified Check-In';
  }
}

/* =====================================================================
   Standard Mark Attendance & Worker Registration
   ===================================================================== */
function openMarkModal() {
  document.getElementById('mark-modal').classList.remove('hidden');
}

function closeMarkModal() {
  document.getElementById('mark-modal').classList.add('hidden');
  document.getElementById('mark-form').reset();
}

async function handleMarkSubmit(e) {
  e.preventDefault();
  const mineId = parseInt(document.getElementById('att-mine').value);
  const workerIdStr = document.getElementById('att-worker').value;
  const workerId = workerIdStr ? parseInt(workerIdStr) : null;
  const date = document.getElementById('att-date').value;
  const shift = document.getElementById('att-shift').value;
  const status = document.getElementById('att-status').value;
  const ot = parseFloat(document.getElementById('att-ot').value) || 0.0;

  try {
    await API.post('/attendance', {
      mine_id: mineId,
      worker_id: workerId,
      record_date: date,
      shift: shift,
      status: status,
      overtime_hours: ot
    });

    showToast('Attendance recorded successfully', 'success');
    closeMarkModal();
    await applyFilters();
  } catch (err) {
    showError(err);
  }
}

function openWorkerModal() {
  document.getElementById('worker-modal').classList.remove('hidden');
}

function closeWorkerModal() {
  document.getElementById('worker-modal').classList.add('hidden');
  document.getElementById('worker-form').reset();
}

async function handleWorkerSubmit(e) {
  e.preventDefault();
  const mineId = parseInt(document.getElementById('w-mine').value);
  const code = document.getElementById('w-code').value.trim();
  const name = document.getElementById('w-name').value.trim();
  const desig = document.getElementById('w-desig').value.trim();
  const contStr = document.getElementById('w-contractor').value;
  const contractorId = contStr ? parseInt(contStr) : null;

  try {
    await API.post('/workers', {
      mine_id: mineId,
      worker_code: code,
      full_name: name,
      designation: desig,
      contractor_id: contractorId
    });

    showToast(`Worker ${name} registered successfully`, 'success');
    closeWorkerModal();
    await loadInitialDropdowns();
  } catch (err) {
    showError(err);
  }
}
