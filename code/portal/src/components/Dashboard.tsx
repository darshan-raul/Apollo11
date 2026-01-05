
import React, { useEffect, useState } from 'react';
import { api } from '../api';
import { useNavigate } from 'react-router-dom';

interface Stage {
    id: number;
    name: string;
    description: string;
    order: number;
}

interface Progress {
    stage_id: number;
    status: 'locked' | 'in_progress' | 'completed';
}

const Dashboard: React.FC = () => {
    const [stages, setStages] = useState<Stage[]>([]);
    const [progress, setProgress] = useState<Progress[]>([]);
    const [loading, setLoading] = useState(true);
    const navigate = useNavigate();

    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        try {
            setError(null);
            const [stagesRes, progressRes] = await Promise.all([
                api.get<Stage[]>('/stages'),
                api.get<Progress[]>('/progress')
            ]);
            setStages(stagesRes.data);
            setProgress(progressRes.data);
        } catch (error: any) {
            console.error("Failed to fetch data", error);
            setError(error.message || "Unknown error occurred");
        } finally {
            setLoading(false);
        }
    };

    const getStatus = (stageId: number) => {
        const prog = progress.find(p => p.stage_id === stageId);
        // Default stage 1 to unlocked if no progress found (or handle via backend logic)
        // But visually we can treat 1 as available if not explicitly locked.
        // Actually, let's treat unset as 'locked' unless stage 1.
        if (stageId === 1 && !prog) return 'unlocked';
        return prog ? prog.status : 'locked';
    };

    const handleStart = async (stageId: number) => {
        try {
            await api.post(`/stages/${stageId}/start`);
            fetchData();
            navigate(`/quiz/${stageId}`);
        } catch (e) {
            console.error(e);
            alert("Failed to start mission stage. Systems unavailable.");
        }
    };

    if (loading) {
        return <div style={{ display: 'flex', justifyContent: 'center', padding: '4rem' }}>Loading Mission Data...</div>;
    }

    if (error) {
        return (
            <div style={{ padding: '2rem', textAlign: 'center' }}>
                <h3 style={{ color: 'var(--error)' }}>Mission Data Unavailable</h3>
                <p>{error}</p>
                <button onClick={fetchData} className="btn btn-primary" style={{ marginTop: '1rem' }}>Retry Connection</button>
            </div>
        );
    }

    return (
        <div className="fade-in">
            <h2 style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '1rem', marginBottom: '2rem' }}>
                Mission Log
            </h2>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '2rem' }}>
                {stages.map(stage => {
                    const status = getStatus(stage.id);
                    const isLocked = status === 'locked';
                    const isCompleted = status === 'completed';
                    const isInProgress = status === 'in_progress' || status === 'unlocked';

                    return (
                        <div key={stage.id} className="glass-panel" style={{
                            padding: '1.5rem',
                            display: 'flex',
                            flexDirection: 'column',
                            opacity: isLocked ? 0.6 : 1,
                            border: isCompleted ? '1px solid var(--success)' : (isInProgress ? '1px solid var(--accent-primary)' : undefined),
                            position: 'relative',
                            overflow: 'hidden'
                        }}>
                            {/* Status Indicator */}
                            <div style={{
                                position: 'absolute',
                                top: '1rem',
                                right: '1rem',
                                fontSize: '0.75rem',
                                fontWeight: 700,
                                color: isCompleted ? 'var(--success)' : (isInProgress ? 'var(--accent-primary)' : 'var(--text-secondary)'),
                                textTransform: 'uppercase',
                                letterSpacing: '1px'
                            }}>
                                {status === 'unlocked' ? 'READY' : status.replace('_', ' ')}
                            </div>

                            <div style={{
                                fontSize: '3rem',
                                fontWeight: 800,
                                color: 'rgba(255,255,255,0.05)',
                                lineHeight: 1,
                                marginBottom: '0.5rem'
                            }}>
                                {String(stage.order).padStart(2, '0')}
                            </div>

                            <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>{stage.name}</h3>
                            <p style={{ color: 'var(--text-secondary)', flex: 1, marginBottom: '1.5rem' }}>{stage.description}</p>

                            <div style={{ marginTop: 'auto' }}>
                                {/* Action Button */}
                                {isLocked ? (
                                    <button className="btn btn-secondary" disabled style={{ width: '100%', opacity: 0.5, cursor: 'not-allowed' }}>
                                        Locked
                                    </button>
                                ) : (
                                    <button
                                        className={isCompleted ? "btn btn-secondary" : "btn btn-primary"}
                                        style={{ width: '100%' }}
                                        onClick={() => isCompleted || isInProgress ? navigate(`/quiz/${stage.id}`) : handleStart(stage.id)}
                                    >
                                        {isCompleted ? 'Replay Mission' : (isInProgress ? 'Resume Mission' : 'Initiate Launch')}
                                    </button>
                                )}
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
};

export default Dashboard;
