# JIS X 0410 地域メッシュコードの PL/pgSQL 関数

以前 [jismesh-to-sql](https://github.com/KotobaMedia/jismesh-to-sql) という地域メッシュコードを
予め生成したテーブルを作成するツールを公開しましたが、こちらは予め生成というより PL/pgSQL で必要のタイミングで
動的に生成する関数集となります。

## 構成

