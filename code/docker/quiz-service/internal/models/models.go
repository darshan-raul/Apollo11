package models

import (
	"time"

	"github.com/google/uuid"
)

type QuizQuestion struct {
	ID            uuid.UUID `json:"id"`
	StageID       int       `json:"stage_id"`
	Question      string    `json:"question"`
	Options       string    `json:"options"` // JSONB stored as string/bytes
	CorrectAnswer string    `json:"correct_answer"`
}

type QuizAttempt struct {
	ID          uuid.UUID `json:"id"`
	UserID      uuid.UUID `json:"user_id"`
	StageID     int       `json:"stage_id"`
	Score       int       `json:"score"`
	Passed      bool      `json:"passed"`
	AttemptedAt time.Time `json:"attempted_at"`
}

type StartQuizRequest struct {
	UserID  string `json:"user_id"`
	StageID int    `json:"stage_id"`
}

type StartQuizResponse struct {
	AttemptID uuid.UUID      `json:"attempt_id"` // Simplified: we might generate an attempt ID upfront or just return questions
	Questions []QuestionView `json:"questions"`
}

type QuestionView struct {
	ID       uuid.UUID `json:"id"`
	Question string    `json:"question"`
	Options  []string  `json:"options"` // parsed from JSONB
}

type SubmitQuizRequest struct {
	UserID  string            `json:"user_id"`
	StageID int               `json:"stage_id"`
	Answers map[string]string `json:"answers"` // QuestionID -> Answer
}

type SubmitQuizResponse struct {
	Score  int  `json:"score"`
	Passed bool `json:"passed"`
}
