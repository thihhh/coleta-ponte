# coleta-ponte

Coleta periódica das condições de trânsito da Ponte Rio-Niterói (tempo de
travessia e trechos com lentidão, por sentido), gravadas num banco Firebase
para consulta posterior.

Roda no GitHub Actions, disparado externamente (`workflow_dispatch`).
Endereço do banco e token ficam só nos segredos do repositório
(`FIREBASE_DB_URL`, `PONTE_TOKEN`) — nunca no código.

Teste local (só imprime, não grava nada):

    dart pub get
    dart run bin/coletar.dart
