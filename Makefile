# サンプルの検査をまとめて実行する: make check
# Go（整形・静的検査・テスト・脆弱性）、YAML、マニフェストのスキーマ、
# GitHub Actions のワークフロー、シェルスクリプト
SCHEMAS := -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
KUBECONFORM := kubeconform -strict -summary $(SCHEMAS)
# そのまま適用するマニフェスト（Compose・Kustomize・Helm の元のファイルは別に描画して調べる）
PLAIN := $(wildcard ch03/*.yaml ch04/*.yaml ch05/*.yaml ch06/*.yaml ch07/copy/*/*.yaml)
# 描画する Kustomize（typo はわざとエラーにする overlay なので、エラーになることを確かめる）
KUSTOMIZE := ch07/kustomize/shared ch07/kustomize/overlays/dev ch07/kustomize/overlays/prod

.PHONY: check go yaml manifests actions shell dry-run
check: go yaml manifests actions shell

go:
	cd app/api && test -z "$$(gofmt -l .)"
	cd app/api && go vet ./...
	cd app/api && golangci-lint run ./...
	cd app/api && go test ./...
	cd app/api && govulncheck ./...

yaml:
	yamllint -s .

manifests:
	@echo "== plain"; $(KUBECONFORM) $(PLAIN)
	@for k in $(KUSTOMIZE); do echo "== $$k"; \
	  kubectl kustomize $$k | $(KUBECONFORM) - || exit 1; done
	@echo "== ch07/kustomize/overlays/typo（エラーになること）"; \
	  ! kubectl kustomize ch07/kustomize/overlays/typo >/dev/null 2>&1
	@echo "== helm"; helm lint ch08/helm/todo
	@helm template todo ch08/helm/todo | $(KUBECONFORM) -
	@helm template todo ch08/helm/todo --set api.replicas=3 --set api.tag=v9 | $(KUBECONFORM) -

actions:
	@if [ -d .github/workflows ]; then actionlint .github/workflows/*.yml; fi

shell:
	shellcheck -x -S warning scripts/*.sh ch*/up.sh

# クラスター（API サーバー）にも確かめてもらう。minikube を起動して第5章の CRD を入れたあとに実行する
dry-run:
	kubectl apply --dry-run=server -f ch06/todo-config.yaml -f ch06/todo-db-pvc.yaml
	kubectl kustomize ch07/kustomize/overlays/dev | kubectl apply --dry-run=server -f -
	helm template todo ch08/helm/todo | kubectl apply --dry-run=server -f -
