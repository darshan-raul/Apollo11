import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../api';
import LoadingScreen from './LoadingScreen';

interface Question {
    id: string;
    question: string;
    options: string[];
}

interface StartResponse {
    questions: Question[];
}

const Quiz: React.FC = () => {
    const { stageId } = useParams();
    const navigate = useNavigate();
    const [questions, setQuestions] = useState<Question[]>([]);
    const [answers, setAnswers] = useState<{ [key: string]: string }>({});
    const [loading, setLoading] = useState(true);
    const [submitting, setSubmitting] = useState(false);

    useEffect(() => {
        const startQuiz = async () => {
            try {
                const res = await api.post<StartResponse>(`/quiz/${stageId}/start`);
                setQuestions(res.data.questions);
            } catch (err: any) {
                console.error(err);
                const msg = err.response?.data?.detail || err.message || "Unknown error";
                alert(`Failed to start quiz: ${msg}`);
            } finally {
                setLoading(false);
            }
        };
        startQuiz();
    }, [stageId]);

    const handleOptionChange = (qId: string, option: string) => {
        setAnswers(prev => ({ ...prev, [qId]: option }));
    };

    const handleSubmit = async () => {
        setSubmitting(true);
        try {
            const res = await api.post(`/quiz/${stageId}/submit`, answers);
            const { passed, score } = res.data;
            alert(`Quiz Finished! Score: ${score}. Passed: ${passed}`);
            if (passed) {
                await api.post(`/stages/${stageId}/complete`);
            }
            navigate('/dashboard');
        } catch (err) {
            console.error(err);
            alert("Error submitting quiz");
        } finally {
            setSubmitting(false);
        }
    };

    if (loading) return <LoadingScreen message={`Preparing Stage ${stageId} Simulation...`} />;

    return (
        <div className="fade-in" style={{ paddingBottom: '5rem' }}>
            <button
                onClick={() => navigate('/dashboard')}
                className="btn btn-secondary"
                style={{ marginBottom: '2rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}
            >
                ← Abort to Dashboard
            </button>

            <h2 style={{
                borderBottom: '1px solid rgba(255,255,255,0.1)',
                paddingBottom: '1rem',
                marginBottom: '2rem',
                display: 'flex',
                alignItems: 'baseline',
                gap: '1rem'
            }}>
                Test Procedure <span style={{ fontSize: '1rem', color: 'var(--text-secondary)', fontWeight: 400 }}>Stage {stageId}</span>
            </h2>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '2rem' }}>
                {questions.map((q, idx) => (
                    <div key={q.id} className="glass-panel" style={{ padding: '2rem' }}>
                        <p style={{
                            fontSize: '1.1rem',
                            marginBottom: '1.5rem',
                            fontWeight: 500,
                            lineHeight: 1.5,
                            display: 'flex',
                            gap: '1rem'
                        }}>
                            <span style={{ color: 'var(--accent-primary)', fontWeight: 700 }}>{String(idx + 1).padStart(2, '0')}</span>
                            {q.question}
                        </p>
                        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                            {q.options.map(opt => {
                                const isSelected = answers[q.id] === opt;
                                return (
                                    <label key={opt} style={{
                                        display: 'flex',
                                        alignItems: 'center',
                                        padding: '1rem',
                                        borderRadius: 'var(--radius-sm)',
                                        border: `1px solid ${isSelected ? 'var(--accent-primary)' : 'rgba(255,255,255,0.1)'}`,
                                        background: isSelected ? 'rgba(59, 130, 246, 0.1)' : 'rgba(255,255,255,0.02)',
                                        cursor: 'pointer',
                                        transition: 'all 0.2s ease'
                                    }}>
                                        <input
                                            type="radio"
                                            name={q.id}
                                            value={opt}
                                            checked={isSelected}
                                            onChange={() => handleOptionChange(q.id, opt)}
                                            style={{ marginRight: '1rem', accentColor: 'var(--accent-primary)' }}
                                        />
                                        {opt}
                                    </label>
                                );
                            })}
                        </div>
                    </div>
                ))}
            </div>

            <div style={{
                position: 'fixed',
                bottom: 0,
                left: 0,
                right: 0,
                padding: '1.5rem',
                background: 'rgba(11, 14, 20, 0.95)',
                backdropFilter: 'blur(10px)',
                borderTop: '1px solid rgba(255,255,255,0.1)',
                display: 'flex',
                justifyContent: 'center',
                zIndex: 10
            }}>
                <div className="container" style={{ display: 'flex', justifyContent: 'flex-end', alignItems: 'center' }}>
                    <div style={{ marginRight: '1.5rem', color: 'var(--text-secondary)' }}>
                        {Object.keys(answers).length} / {questions.length} Answered
                    </div>
                    <button
                        onClick={handleSubmit}
                        className="btn btn-primary"
                        disabled={submitting || Object.keys(answers).length < questions.length}
                        style={{
                            opacity: Object.keys(answers).length < questions.length ? 0.5 : 1,
                            minWidth: '200px'
                        }}
                    >
                        {submitting ? 'Transmitting Results...' : 'Submit Mission Report'}
                    </button>
                </div>
            </div>
        </div>
    );
};

export default Quiz;
