package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Todo は1件の Todo。
type Todo struct {
	ID    int64  `json:"id"`
	Title string `json:"title"`
	Done  bool   `json:"done"`
}

// errNotFound は指定した ID の Todo が無いことを表す。
var errNotFound = errors.New("todo not found")

// Store は Todo の保存先。本番は PostgreSQL、テストはメモリ。
type Store interface {
	Ping(ctx context.Context) error
	List(ctx context.Context) ([]Todo, error)
	Create(ctx context.Context, title string) (Todo, error)
	SetDone(ctx context.Context, id int64, done bool) (Todo, error)
	Delete(ctx context.Context, id int64) error
}

func newMux(store Store, cfg config) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /readyz", readyz(store))
	mux.HandleFunc("GET /api/config", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"title": cfg.AppTitle})
	})
	mux.HandleFunc("GET /api/todos", func(w http.ResponseWriter, r *http.Request) {
		todos, err := store.List(r.Context())
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, todos)
	})
	mux.HandleFunc("POST /api/todos", func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Title string `json:"title"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil || strings.TrimSpace(in.Title) == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "title is required"})
			return
		}
		todo, err := store.Create(r.Context(), strings.TrimSpace(in.Title))
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, todo)
	})
	mux.HandleFunc("PATCH /api/todos/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := pathID(w, r)
		if !ok {
			return
		}
		var in struct {
			Done bool `json:"done"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid body"})
			return
		}
		todo, err := store.SetDone(r.Context(), id, in.Done)
		if errors.Is(err, errNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		if err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, todo)
	})
	mux.HandleFunc("DELETE /api/todos/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, ok := pathID(w, r)
		if !ok {
			return
		}
		err := store.Delete(r.Context(), id)
		if errors.Is(err, errNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
			return
		}
		if err != nil {
			serverError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	return mux
}

// #region readyz
// readyz は DB に届くかを確かめる。届かない間は 503 を返し、
// Kubernetes の readinessProbe がこの Pod に通信を送らないようにする。
func readyz(store Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := store.Ping(ctx); err != nil {
			log.Printf("not ready: %v", cause(err))
			msg := map[string]string{"error": err.Error()}
			writeJSON(w, http.StatusServiceUnavailable, msg)
			return
		}
		msg := map[string]string{"status": "ready"}
		writeJSON(w, http.StatusOK, msg)
	}
}

// #endregion readyz

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid id"})
		return 0, false
	}
	return id, true
}

func serverError(w http.ResponseWriter, err error) {
	log.Printf("error: %v", err)
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// statusRecorder は応答のステータスコードを控える（アクセスログ用）。
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// accessLog は受けたリクエストを1行ずつ標準出力に出す。
// 送り元のアドレス（remote）で、どこを通って届いたかを確かめられる。
// /healthz と /readyz は数秒ごとに届くので出さない。
func accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			return
		}
		log.Printf("access remote=%s method=%s path=%s status=%d", r.RemoteAddr, r.Method, r.URL.Path, rec.status)
	})
}
