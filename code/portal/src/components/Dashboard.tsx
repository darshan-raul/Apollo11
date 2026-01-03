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
    const navigate = useNavigate();

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        try {
            const [stagesRes, progressRes] = await Promise.all([
                api.get<Stage[]>('/stages'),
                api.get<Progress[]>('/progress')
            ]);
            setStages(stagesRes.data);
            setProgress(progressRes.data);
        } catch (error) {
            console.error("Failed to fetch data", error);
        }
    };

    const getStatus = (stageId: number) => {
        const prog = progress.find(p => p.stage_id === stageId);
        return prog ? prog.status : 'locked';
    };

    const handleStart = async (stageId: number) => {
        try {
            await api.post(`/stages/${stageId}/start`);
            // refresh
            fetchData();
            navigate(`/quiz/${stageId}`);
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <div>
            <h2>Mission Stages</h2>
            <div style={{ display: 'grid', gap: '15px' }}>
                {stages.map(stage => {
                    const status = getStatus(stage.id);
                    // Unlock first stage by default if locked? Or assume backend handles logic.
                    // Simplified: User can click if not locked, OR if it's the first one and locked (start it).
                    // Actually implementation detail: stage 1 should be unlocked. Backend logic needed.
                    // For UI, we permit clicking.
                    return (
                        <div key={stage.id} style={{ border: '1px solid #ccc', padding: '15px', borderRadius: '8px' }}>
                            <h3>{stage.order}. {stage.name}</h3>
                            <p>{stage.description}</p>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <span>Status: <strong>{status.toUpperCase()}</strong></span>
                                {status !== 'locked' && (
                                    <button onClick={() => navigate(`/quiz/${stage.id}`)}>
                                        {status === 'completed' ? 'Retake Quiz' : 'Continue Mission'}
                                    </button>
                                )}
                                {status === 'locked' && stage.id === 1 && ( // Auto unlock 1
                                    <button onClick={() => handleStart(stage.id)}>
                                        Ignition
                                    </button>
                                )}
                                {status === 'locked' && stage.id > 1 && (
                                    <button disabled>Locked</button>
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
