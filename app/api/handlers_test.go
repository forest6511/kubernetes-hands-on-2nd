package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// memStore はテスト用のメモリの保存先。
type memStore struct {
	mu      sync.Mutex
	todos   []Todo
	next    int64
	pingErr error
}

func (m *memStore) Ping(context.Context) error { return m.pingErr }

func (m *memStore) List(context.Context) ([]Todo, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]Todo{}, m.todos...), nil
}

func (m *memStore) Create(_ context.Context, title string) (Todo, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.next++
	t := Todo{ID: m.next, Title: title}
	m.todos = append(m.todos, t)
	return t, nil
}

func (m *memStore) SetDone(_ context.Context, id int64, done bool) (Todo, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range m.todos {
		if m.todos[i].ID == id {
			m.todos[i].Done = done
			return m.todos[i], nil
		}
	}
	return Todo{}, errNotFound
}

func (m *memStore) Delete(_ context.Context, id int64) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i := range m.todos {
		if m.todos[i].ID == id {
			m.todos = append(m.todos[:i], m.todos[i+1:]...)
			return nil
		}
	}
	return errNotFound
}

func do(t *testing.T, h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestCRUD(t *testing.T) {
	h := newMux(&memStore{}, config{AppTitle: "Todo"})
	if rec := do(t, h, "POST", "/api/todos", `{"title":"牛乳を買う"}`); rec.Code != http.StatusCreated {
		t.Fatalf("create: got %d", rec.Code)
	}
	if rec := do(t, h, "GET", "/api/todos", ""); !strings.Contains(rec.Body.String(), "牛乳を買う") {
		t.Fatalf("list: got %s", rec.Body.String())
	}
	if rec := do(t, h, "PATCH", "/api/todos/1", `{"done":true}`); !strings.Contains(rec.Body.String(), `"done":true`) {
		t.Fatalf("done: got %s", rec.Body.String())
	}
	if rec := do(t, h, "DELETE", "/api/todos/1", ""); rec.Code != http.StatusNoContent {
		t.Fatalf("delete: got %d", rec.Code)
	}
	if rec := do(t, h, "DELETE", "/api/todos/1", ""); rec.Code != http.StatusNotFound {
		t.Fatalf("delete again: got %d", rec.Code)
	}
}

func TestCreateRequiresTitle(t *testing.T) {
	h := newMux(&memStore{}, config{})
	if rec := do(t, h, "POST", "/api/todos", `{"title":"  "}`); rec.Code != http.StatusBadRequest {
		t.Fatalf("got %d", rec.Code)
	}
}

func TestReadyz(t *testing.T) {
	store := &memStore{pingErr: errors.New("lookup todo-db: no such host")}
	h := newMux(store, config{})
	if rec := do(t, h, "GET", "/readyz", ""); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("not ready: got %d", rec.Code)
	}
	store.pingErr = nil
	if rec := do(t, h, "GET", "/readyz", ""); rec.Code != http.StatusOK {
		t.Fatalf("ready: got %d", rec.Code)
	}
}

func TestConfig(t *testing.T) {
	h := newMux(&memStore{}, config{AppTitle: "Todo（開発）"})
	if rec := do(t, h, "GET", "/api/config", ""); !strings.Contains(rec.Body.String(), "Todo（開発）") {
		t.Fatalf("got %s", rec.Body.String())
	}
}
