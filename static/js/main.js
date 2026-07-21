/**
 * main.js
 * Small shared behaviours used across pages. Page-specific logic
 * (chart rendering, form toggling, AJAX balance lookup) lives in
 * inline <script> blocks within each template, next to the markup
 * it controls.
 */

// Auto-dismiss flash alerts after 5 seconds
document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.app-alert').forEach(function (alertEl) {
        setTimeout(function () {
            const bsAlert = bootstrap.Alert.getOrCreateInstance(alertEl);
            bsAlert.close();
        }, 5000);
    });
});
