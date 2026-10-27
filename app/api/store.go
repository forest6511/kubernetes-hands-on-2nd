package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/url"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// pgStore は PostgreSQL に Todo を保存する。
type pgStore struct {
	pool *pgxpool.Pool
}

func newPGStore(ctx context.Context, cfg config) (*pgStore, error) {
	dsn := (&url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(cfg.DBUser, cfg.DBPassword),
		Host:     net.JoinHostPort(cfg.DBHost, cfg.DBPort),
		Path:     "/" + cfg.DBName,
		RawQuery: "sslmode=disable&connect_timeout=2",
	}).String()
	// pgxpool.New はまだ接続しない（DB が無くても起動できる）
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	return &pgStore{pool: pool}, nil
}

func (s *pgStore) Close() { s.pool.Close() }

// prepareLoop は表を作れるまで interval ごとに試す。失敗の理由はログに出す。
func (s *pgStore) prepareLoop(ctx context.Context, interval time.Duration) {
	for {
		err := s.prepare(ctx)
		if err == nil {
			log.Printf("db ready")
			return
		}
		log.Printf("db not ready: %v", cause(err))
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// cause は、DB に届かなかった理由のうち根本のもの（名前解決・接続の失敗）を返す。
// ログを1行で読めるようにするため。
func cause(err error) error {
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return dnsErr
	}
	var opErr *net.OpError
	if errors.As(err, &opErr) {
		return opErr
	}
	return err
}

func (s *pgStore) prepare(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	_, err := s.pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS todos (
		id BIGSERIAL PRIMARY KEY,
		title TEXT NOT NULL,
		done BOOLEAN NOT NULL DEFAULT FALSE)`)
	return err
}

// Ping は DB に届くかを確かめ、表が無ければ作る。
// DB が作り直されて空になったときも、ここで表が戻る。
func (s *pgStore) Ping(ctx context.Context) error {
	if err := s.pool.Ping(ctx); err != nil {
		return err
	}
	return s.prepare(ctx)
}

// withTable は fn を実行し、表が無いエラー（DB が作り直された直後）なら表を作ってもう一度だけ試す。
func (s *pgStore) withTable(ctx context.Context, fn func() error) error {
	err := fn()
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "42P01" {
		if err := s.prepare(ctx); err != nil {
			return err
		}
		return fn()
	}
	return err
}

func (s *pgStore) List(ctx context.Context) ([]Todo, error) {
	var todos []Todo
	err := s.withTable(ctx, func() error {
		rows, err := s.pool.Query(ctx, `SELECT id, title, done FROM todos ORDER BY id`)
		if err != nil {
			return err
		}
		todos, err = pgx.CollectRows(rows, pgx.RowToStructByPos[Todo])
		return err
	})
	if err != nil {
		return nil, err
	}
	if todos == nil {
		todos = []Todo{}
	}
	return todos, nil
}

func (s *pgStore) Create(ctx context.Context, title string) (Todo, error) {
	var t Todo
	err := s.withTable(ctx, func() error {
		return s.pool.QueryRow(ctx,
			`INSERT INTO todos (title) VALUES ($1) RETURNING id, title, done`, title).
			Scan(&t.ID, &t.Title, &t.Done)
	})
	return t, err
}

func (s *pgStore) SetDone(ctx context.Context, id int64, done bool) (Todo, error) {
	var t Todo
	err := s.pool.QueryRow(ctx,
		`UPDATE todos SET done = $2 WHERE id = $1 RETURNING id, title, done`, id, done).
		Scan(&t.ID, &t.Title, &t.Done)
	if errors.Is(err, pgx.ErrNoRows) {
		return Todo{}, errNotFound
	}
	return t, err
}

func (s *pgStore) Delete(ctx context.Context, id int64) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM todos WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("delete %d: %w", id, errNotFound)
	}
	return nil
}
