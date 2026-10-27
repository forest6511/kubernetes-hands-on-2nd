// todo-api は Todo アプリの API サーバー。DB（PostgreSQL）に Todo を保存する。
// 設定はすべて環境変数から読む（Kubernetes の ConfigMap・Secret から渡すため）。
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// #region config
// config は環境変数から読む設定。
// DB が無くても HTTP サーバーは先に起動する。
type config struct {
	Port       string // HTTP で待ち受けるポート
	AppTitle   string // 画面の見出し（/api/config で返す）
	DBHost     string // DB の宛先。Kubernetes では Service の名前を書く
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
}

func loadConfig() config {
	return config{
		Port:       getenv("PORT", "8080"),
		AppTitle:   getenv("APP_TITLE", "Todo"),
		DBHost:     getenv("DB_HOST", "todo-db"),
		DBPort:     getenv("DB_PORT", "5432"),
		DBUser:     getenv("DB_USER", "todo"),
		DBPassword: os.Getenv("DB_PASSWORD"),
		DBName:     getenv("DB_NAME", "todo"),
	}
}

// #endregion config

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	// 時刻は付けない（kubectl logs --timestamps で付けられる）。1行を短くして読みやすくする
	log.SetFlags(0)
	cfg := loadConfig()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	store, err := newPGStore(ctx, cfg)
	if err != nil {
		log.Fatalf("db config: %v", err)
	}
	defer store.Close()
	// DB の準備（表の作成）は裏で繰り返す。DB に届かない間は /readyz が 503 を返す
	go store.prepareLoop(ctx, 3*time.Second)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           accessLog(newMux(store, cfg)),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()
	log.Printf("todo-api listening on :%s (db=%s:%s)", cfg.Port, cfg.DBHost, cfg.DBPort)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}
