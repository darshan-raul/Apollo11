// Apollo 11 Astronaut Onboarding Frontend JavaScript

// Global app configuration
const APP_CONFIG = {
    apiBaseUrl: '/api',
    tokenKey: 'access_token'
};

// Utility functions
const Utils = {
    // Get stored authentication token
    getToken() {
        return localStorage.getItem(APP_CONFIG.tokenKey);
    },

    // Set authentication token
    setToken(token) {
        localStorage.setItem(APP_CONFIG.tokenKey, token);
    },

    // Remove authentication token
    removeToken() {
        localStorage.removeItem(APP_CONFIG.tokenKey);
    },

    // Check if user is authenticated
    isAuthenticated() {
        return !!this.getToken();
    },

    // Make authenticated API request
    async apiRequest(url, options = {}) {
        const token = this.getToken();
        const defaultOptions = {
            headers: {
                'Content-Type': 'application/json',
                ...(token && { 'Authorization': `Bearer ${token}` })
            }
        };

        const response = await fetch(url, { ...defaultOptions, ...options });
        
        if (response.status === 401) {
            this.removeToken();
            window.location.href = '/login';
            return null;
        }

        return response;
    },

    // Show loading spinner
    showLoading(element) {
        if (element) {
            element.innerHTML = `
                <div class="text-center">
                    <div class="spinner-border text-primary" role="status">
                        <span class="visually-hidden">Loading...</span>
                    </div>
                </div>
            `;
        }
    },

    // Show success message
    showSuccess(message, duration = 3000) {
        this.showAlert(message, 'success', duration);
    },

    // Show error message
    showError(message, duration = 5000) {
        this.showAlert(message, 'danger', duration);
    },

    // Show alert message
    showAlert(message, type = 'info', duration = 3000) {
        const alertDiv = document.createElement('div');
        alertDiv.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
        alertDiv.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
        alertDiv.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;

        document.body.appendChild(alertDiv);

        if (duration > 0) {
            setTimeout(() => {
                if (alertDiv.parentNode) {
                    alertDiv.remove();
                }
            }, duration);
        }
    },

    // Format date
    formatDate(dateString) {
        const date = new Date(dateString);
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    },

    // Format duration
    formatDuration(seconds) {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = seconds % 60;

        if (hours > 0) {
            return `${hours}h ${minutes}m ${secs}s`;
        } else if (minutes > 0) {
            return `${minutes}m ${secs}s`;
        } else {
            return `${secs}s`;
        }
    }
};

// Stage management
const StageManager = {
    // Start a stage simulation
    async startStage(stageId) {
        try {
            const response = await Utils.apiRequest(`${APP_CONFIG.apiBaseUrl}/stage/${stageId}/start`, {
                method: 'POST'
            });

            if (response && response.ok) {
                const data = await response.json();
                Utils.showSuccess('Stage simulation started successfully!');
                return data;
            } else if (response) {
                const error = await response.json();
                Utils.showError('Failed to start stage: ' + error.detail);
            }
        } catch (error) {
            Utils.showError('Failed to start stage: ' + error.message);
        }
        return null;
    },

    // Get user progress
    async getUserProgress() {
        try {
            const response = await Utils.apiRequest(`${APP_CONFIG.apiBaseUrl}/user/progress`);

            if (response && response.ok) {
                return await response.json();
            }
        } catch (error) {
            console.error('Failed to get user progress:', error);
        }
        return null;
    },

    // Poll for simulation results
    startPolling(stageId, callback) {
        const interval = setInterval(async () => {
            const progress = await this.getUserProgress();
            if (progress) {
                const stageProgress = progress.progress.find(p => p.stage_id === stageId);
                if (stageProgress && stageProgress.status !== 'in_progress') {
                    clearInterval(interval);
                    if (callback) {
                        callback(stageProgress);
                    }
                }
            }
        }, 2000);

        return interval;
    }
};

// User management
const UserManager = {
    // Login user
    async login(username, password) {
        try {
            const response = await fetch(`${APP_CONFIG.apiBaseUrl}/login`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ username, password })
            });

            if (response.ok) {
                const data = await response.json();
                Utils.setToken(data.access_token);
                return data;
            } else {
                const error = await response.json();
                throw new Error(error.detail);
            }
        } catch (error) {
            throw error;
        }
    },

    // Register user
    async register(userData) {
        try {
            const response = await fetch(`${APP_CONFIG.apiBaseUrl}/register`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(userData)
            });

            if (response.ok) {
                return await response.json();
            } else {
                const error = await response.json();
                throw new Error(error.detail);
            }
        } catch (error) {
            throw error;
        }
    },

    // Logout user
    logout() {
        Utils.removeToken();
        window.location.href = '/';
    }
};

// Dashboard functionality
const Dashboard = {
    // Initialize dashboard
    init() {
        this.loadUserProgress();
        this.setupEventListeners();
    },

    // Load user progress
    async loadUserProgress() {
        const progress = await StageManager.getUserProgress();
        if (progress) {
            this.updateProgressDisplay(progress);
        }
    },

    // Update progress display
    updateProgressDisplay(progress) {
        // Update progress bars and statistics
        const completedCount = progress.progress.filter(p => p.status === 'completed').length;
        const progressPercent = (completedCount / 11) * 100;

        const progressBar = document.querySelector('.progress-bar');
        if (progressBar) {
            progressBar.style.width = `${progressPercent}%`;
            progressBar.textContent = `${progressPercent.toFixed(1)}%`;
        }

        // Update stage cards
        progress.progress.forEach(stageProgress => {
            const stageCard = document.querySelector(`[data-stage-id="${stageProgress.stage_id}"]`);
            if (stageCard) {
                this.updateStageCard(stageCard, stageProgress);
            }
        });
    },

    // Update individual stage card
    updateStageCard(card, progress) {
        const statusBadge = card.querySelector('.badge');
        const statusText = card.querySelector('.status-text');
        const actionButton = card.querySelector('.action-button');

        if (statusBadge) {
            statusBadge.className = `badge ${this.getStatusClass(progress.status)}`;
            statusBadge.innerHTML = this.getStatusIcon(progress.status) + ' ' + progress.status.charAt(0).toUpperCase() + progress.status.slice(1);
        }

        if (actionButton) {
            actionButton.innerHTML = this.getActionButton(progress);
        }
    },

    // Get status CSS class
    getStatusClass(status) {
        const classes = {
            'completed': 'bg-success',
            'available': 'bg-primary',
            'in_progress': 'bg-warning',
            'failed': 'bg-danger',
            'locked': 'bg-secondary'
        };
        return classes[status] || 'bg-secondary';
    },

    // Get status icon
    getStatusIcon(status) {
        const icons = {
            'completed': '<i class="fas fa-check"></i>',
            'available': '<i class="fas fa-play"></i>',
            'in_progress': '<i class="fas fa-clock"></i>',
            'failed': '<i class="fas fa-exclamation-triangle"></i>',
            'locked': '<i class="fas fa-lock"></i>'
        };
        return icons[status] || '<i class="fas fa-question"></i>';
    },

    // Get action button HTML
    getActionButton(progress) {
        switch (progress.status) {
            case 'available':
                return `<a href="/stage/${progress.stage_id}" class="btn btn-primary btn-sm"><i class="fas fa-play"></i> Start Stage</a>`;
            case 'in_progress':
                return `<a href="/stage/${progress.stage_id}" class="btn btn-warning btn-sm"><i class="fas fa-arrow-right"></i> Continue</a>`;
            case 'completed':
                return `<span class="text-success"><i class="fas fa-check-circle"></i> Completed</span>`;
            case 'failed':
                return `<a href="/stage/${progress.stage_id}" class="btn btn-warning btn-sm"><i class="fas fa-redo"></i> Retry</a>`;
            default:
                return `<span class="text-muted"><i class="fas fa-lock"></i> Locked</span>`;
        }
    },

    // Setup event listeners
    setupEventListeners() {
        // Add any dashboard-specific event listeners here
    }
};

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    // Check authentication status
    if (!Utils.isAuthenticated() && window.location.pathname !== '/login' && window.location.pathname !== '/register' && window.location.pathname !== '/') {
        window.location.href = '/login';
    }

    // Initialize dashboard if on dashboard page
    if (window.location.pathname === '/dashboard') {
        Dashboard.init();
    }
});

// Export for global access
window.Utils = Utils;
window.StageManager = StageManager;
window.UserManager = UserManager;
window.Dashboard = Dashboard;
