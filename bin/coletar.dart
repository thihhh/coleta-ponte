// Coleta periódica das condições da Ponte Rio-Niterói (2026-10-14).
//
// Roda no GitHub Actions (.github/workflows/coleta.yml), disparado pelo
// cron-job.org em dias úteis. Consulta a mesma API do card da Ponte e
// grava uma leitura ENXUTA (~1 KB) no Firebase, em
// `leituras_ponte/$PONTE_TOKEN` -- mesmo modelo de "link secreto" do resto
// do projeto (o token só existe como segredo do GitHub e no app).
//
// Variáveis de ambiente: FIREBASE_DB_URL, PONTE_TOKEN. Sem as duas, só
// imprime a leitura (modo teste local).
import 'dart:convert';
import 'dart:io';

import '../lib/parse_condicoes_ponte.dart';

const _url = 'https://www.ecoviasponte.com.br/api/playful-map';

Future<String?> _consultar() async {
  // A API pendura ~1 em 4 chamadas; 3 tentativas com timeout de 20 s.
  for (var tentativa = 1; tentativa <= 3; tentativa++) {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await cliente.getUrl(Uri.parse(_url)).timeout(const Duration(seconds: 20));
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final corpo = await resp.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
      stdout.writeln('Tentativa $tentativa: HTTP ${resp.statusCode}, ${corpo.length} bytes');
      if (resp.statusCode == 200) return corpo;
      // 403 é o bloqueio da Akamai a ESTE endereço: repetir na mesma máquina
      // não adianta. Quem tenta de novo é o próximo job, noutra máquina.
      if (resp.statusCode == 403) return null;
    } catch (e) {
      stdout.writeln('Tentativa $tentativa falhou: $e');
    } finally {
      cliente.close(force: true);
    }
  }
  return null;
}

Map<String, Object?> _leitura(CondicoesPonte c, DateTime coletadoEm) => {
      'coletadoEm': coletadoEm.millisecondsSinceEpoch,
      'medidoEm': c.atualizadoEm?.millisecondsSinceEpoch,
      'sentidos': [
        for (final s in c.sentidos)
          {
            'sentido': s.sentido,
            'minutos': s.minutos,
            'nivel': s.condicaoNivel,
            'condicao': s.condicaoTexto,
            if (s.motivo != null && s.motivo!.isNotEmpty) 'motivo': s.motivo,
            'trechos': [
              for (final t in s.trechos)
                if (t.nivel > 1)
                  {
                    'kmInicial': t.kmInicial,
                    'kmFinal': t.kmFinal,
                    'nivel': t.nivel,
                    if (t.motivo != null && t.motivo!.isNotEmpty) 'motivo': t.motivo,
                  },
            ],
          },
      ],
    };

Future<void> main() async {
  final agora = DateTime.now();
  final corpo = await _consultar();
  final db = Platform.environment['FIREBASE_DB_URL'];
  final token = Platform.environment['PONTE_TOKEN'];

  // ULTIMA_TENTATIVA=1 só no último job do workflow. Os anteriores, sem
  // resposta, saem com erro sem gravar nada (o próximo job tenta noutra
  // máquina); só o último registra a falha.
  final ultima = Platform.environment['ULTIMA_TENTATIVA'] != '0';
  if (corpo == null && !ultima) {
    stdout.writeln('Sem resposta nesta máquina; o próximo job tenta de novo.');
    exit(1);
  }
  Map<String, Object?> leitura;
  if (corpo == null) {
    // Registra a falha também: um buraco explicado vale mais que um buraco mudo.
    leitura = {'coletadoEm': agora.millisecondsSinceEpoch, 'erro': 'sem resposta da Ecovias'};
  } else {
    leitura = _leitura(parseCondicoesPonte(jsonDecode(corpo)), agora);
  }
  final json = jsonEncode(leitura);
  stdout.writeln(json);

  if (db == null || db.isEmpty || token == null || token.isEmpty) {
    stdout.writeln('FIREBASE_DB_URL/PONTE_TOKEN ausentes: só teste, nada gravado.');
    exit(corpo == null ? 1 : 0);
  }
  final cliente = HttpClient();
  try {
    final base = db.endsWith('/') ? db.substring(0, db.length - 1) : db;
    final req = await cliente.postUrl(Uri.parse('$base/leituras_ponte/$token.json'));
    req.headers.contentType = ContentType.json;
    req.write(json);
    final resp = await req.close();
    final r = await resp.transform(utf8.decoder).join();
    stdout.writeln('Firebase: HTTP ${resp.statusCode} $r');
    if (resp.statusCode != 200) exit(1);
  } finally {
    cliente.close(force: true);
  }
  if (corpo == null) exit(1);
}
