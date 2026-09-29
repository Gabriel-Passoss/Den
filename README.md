# Den

Workspace desktop para conversar com Claude Code e OpenCode, revisar alterações e executar comandos de projeto.

## React + Tauri (migração)

A fundação desktop vive em `src/` e `src-tauri/`. O app Swift em `Den.xcodeproj` continua disponível durante a migração. Consulte o [plano e a referência visual](docs/migrations/2026-09-29-swift-para-tauri-react.md).

Pré-requisitos: macOS 26.6 ou mais recente, Xcode/Command Line Tools, Node **24.18.1** (`.nvmrc`) e Rust instalado via [rustup](https://rustup.rs/). `rust-toolchain.toml` fixa a versão e instala rustfmt/clippy. Após instalar Rust, carregue seu ambiente com `source "$HOME/.cargo/env"`.

```sh
npm ci
npm run dev
```

A janela mostra o resultado de `runtime_info`, um comando real do Rust chamado por IPC. **Verificar conexão** repete a chamada. `npm run dev:web` abre apenas a prévia web e informa que o backend desktop está ausente.

```sh
npm test
npm run lint
npm run format:check
npm run build
```

`npm run build` compila um executável de produção em `src-tauri/target/release/den-desktop`. Empacotamento `.app`/`.dmg` e assinatura serão adicionados na etapa de corte. O scaffold usa controles de janela nativos, não acessa sessões/preferências Swift e encerra ao fechar sua única janela.

O frontend tem apenas permissão para consultar metadados do runtime na janela local `main`. Não há plugins de shell, filesystem ou conteúdo remoto. A configuração de desenvolvimento permite o servidor Vite local; produção usa CSP restrita.

Scripts por camada: `test:web`, `test:rust` e `build:web`. `npm run format` formata o scaffold e Rust; os arquivos Swift e documentos históricos ficam fora da formatação automática.

## Swift (referência atual)

Abra `Den.xcodeproj` no Xcode. A CI existente continua executando HarnessKit, testes do app e XCUITest.

```sh
swift test --package-path Packages/HarnessKit
xcodebuild test -project Den.xcodeproj -scheme Den -destination 'platform=macOS'
```
