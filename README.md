# App Kids

App Flutter para pais gerirem rotinas, tarefas, atividades, aprendizado e a mesada (em R$) dos filhos.
Backend: Supabase (Auth + Postgres com RLS).

> O dinheiro em R$ é um **controle**: mesada, ganhos por tarefa, poupança e metas. Os pagamentos reais
> (PIX ou espécie) são feitos pelos responsáveis, que registram o pagamento no app.

## Rodar localmente

```
flutter pub get
flutter run --dart-define=SUPABASE_ANON_KEY=<chave anon/publishable do projeto>
```

## Banco de dados

As migrations estão em [supabase/migrations](supabase/migrations) e devem ser aplicadas em ordem.
Todas as tabelas usam RLS: cada responsável só acessa os dados da própria família.

## CI e GitHub Pages

- `ci.yml`: `flutter analyze` e `flutter test` em cada push/PR.
- `pages.yml`: gera o build web e publica no GitHub Pages a cada push na `main`.

Configuração necessária no repositório:
1. **Settings → Pages → Source: GitHub Actions**.
2. **Settings → Secrets and variables → Actions → New repository secret**: `SUPABASE_ANON_KEY`.
3. No Supabase, em **Authentication → URL Configuration**, adicione a URL do Pages em *Site URL / Redirect URLs*.
