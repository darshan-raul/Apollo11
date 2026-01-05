import React, { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { api } from '../api';

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
                // Mark stage complete in core API logic? 
                // Core API `submit_quiz` logic doesn't explicitly call `complete_stage` unless we added it.
                // But let's assume if passed, we redirect to dashboard.
                // We should probably call /complete if we want to be explicit, or backend handles it.
                // Let's call complete for safety if backend doesn't do it auto (my backend implementation didn't link them perfectly).
                // "Core: Update DB to completed? ... pass" in my comments.
                // I'll add a call here to safely complete it if passed.
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

    if (loading) return <div>Loading Quiz...</div>;

    return (
        <div>
            <button onClick={() => navigate('/dashboard')}>Back to Dashboard</button>
            <h2>Quiz for Stage {stageId}</h2>
            {questions.map((q, idx) => (
                <div key={q.id} style={{ marginBottom: '20px', padding: '10px', border: '1px solid #444' }}>
                    <p><strong>{idx + 1}. {q.question}</strong></p>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '5px' }}>
                        {q.options.map(opt => (
                            <label key={opt}>
                                <input
                                    type="radio"
                                    name={q.id}
                                    value={opt}
                                    checked={answers[q.id] === opt}
                                    onChange={() => handleOptionChange(q.id, opt)}
                                />
                                {opt}
                            </label>
                        ))}
                    </div>
                </div>
            ))}
            <button onClick={handleSubmit} disabled={submitting || Object.keys(answers).length < questions.length}>
                {submitting ? 'Submitting...' : 'Submit Answers'}
            </button>
        </div>
    );
};

export default Quiz;
