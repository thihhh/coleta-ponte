/// Um trecho de quilometragem da Ponte com sua condição, num sentido.
///
/// A API entrega a condição fatiada por faixa de km (`InitialKM`/`FinalKM`)
/// em vez de um status único — é isso que permite desenhar o diagrama com a
/// lentidão no lugar certo, e não só dizer "tem lentidão em algum ponto".
class TrechoPonte {
  const TrechoPonte({
    required this.kmInicial,
    required this.kmFinal,
    required this.nivel,
    required this.texto,
    this.corHex,
    this.motivo,
  });

  final double kmInicial;
  final double kmFinal;

  /// 1 = Normal, 2 = Lento, ... 6 = Pare e siga. Ver `status_ponte.dart`.
  final int nivel;

  /// Texto cru da API ("Normal"/"Slow"/...). A tradução é responsabilidade de
  /// quem exibe (`nomeCondicaoPonte`), não do parser.
  final String texto;

  final String? corHex;
  final String? motivo;

  bool get cobre => kmFinal > kmInicial;

  @override
  String toString() => 'TrechoPonte($kmInicial-$kmFinal, nivel $nivel)';
}

/// Tipo de um ponto de referência ao longo da Ponte.
enum TipoMarcoPonte {
  /// Lugar com nome próprio ao longo do vão (Vão Central, Grande Curva...) —
  /// vira rótulo vertical no diagrama, como no mapa oficial.
  referencia,

  /// Serviço/instalação (polícia, SAU, pedágio) — informativo, fora do
  /// desenho das pistas pra não competir com as faixas de condição.
  servico,
}

/// Ponto de referência num quilômetro específico da Ponte.
class MarcoPonte {
  const MarcoPonte({required this.km, required this.nome, required this.tipo});

  final double km;
  final String nome;
  final TipoMarcoPonte tipo;

  @override
  String toString() => 'MarcoPonte($nome, km $km)';
}

/// Condição de travessia da Ponte Rio-Niterói num sentido.
///
/// Origem do dado: API pública do app oficial da concessionária
/// (`ecoviasponte.com.br/api/playful-map`, ver `PonteService`). O
/// [sentido] é a CIDADE DE DESTINO ("Rio de Janeiro" / "Niterói"), que é
/// como o app oficial rotula as duas colunas.
class CondicaoPonte {
  const CondicaoPonte({
    required this.sentido,
    required this.minutos,
    required this.condicaoTexto,
    required this.condicaoNivel,
    this.corHex,
    this.motivo,
    this.trechos = const [],
    this.climaTexto,
  });

  /// Cidade de destino — "Rio de Janeiro" ou "Niterói".
  final String sentido;

  /// Tempo de travessia em minutos.
  final int minutos;

  /// Texto da condição vindo da API ("Normal", "Lento", ...). Vazio quando a
  /// API não reportou condição pra esse sentido (só o tempo).
  final String condicaoTexto;

  /// Nível numérico da condição (1 = Normal; maior = pior). 0 = desconhecido.
  /// É por ele que se escolhe o PIOR trecho do sentido — ver
  /// [parseCondicoesPonte].
  final int condicaoNivel;

  /// Cor que a própria API associa à condição (ex. `#92d050`). Preservada em
  /// vez de recolorir por conta própria: é a mesma cor que o app oficial e o
  /// site mostram, então bate com o que o usuário já conhece.
  final String? corHex;

  /// Descrição da ocorrência quando existe (campo `Reason` da API, vazio em
  /// condição normal) — ex. acidente/obra num trecho.
  final String? motivo;

  /// Todos os trechos de km deste sentido, em ordem crescente de km — a
  /// matéria-prima do diagrama. [condicaoTexto]/[condicaoNivel] continuam
  /// sendo o resumo (pior trecho) usado pelo card da Tela Inicial.
  final List<TrechoPonte> trechos;

  /// Condição do tempo neste sentido, crua da API ("Good"/"Rain"/...) —
  /// traduzida por `nomeClimaPonte` na hora de exibir.
  final String? climaTexto;

  @override
  String toString() => 'CondicaoPonte($sentido, ${minutos}min, $condicaoTexto)';
}

/// Resultado completo de uma consulta.
class CondicoesPonte {
  const CondicoesPonte({
    required this.sentidos,
    this.atualizadoEm,
    this.kmInicial,
    this.kmFinal,
    this.marcos = const [],
  });

  final List<CondicaoPonte> sentidos;

  /// Quando a concessionária atualizou a medição (não quando consultamos).
  final DateTime? atualizadoEm;

  /// Extremos de quilometragem da Ponte (`Road.InitialKM`/`FinalKM`, hoje 321
  /// a 334,5). É a ESCALA do diagrama: sem ela não há como posicionar um
  /// trecho. Vem da resposta, não fixo no código — se a concessionária
  /// reescalar, o desenho acompanha.
  final double? kmInicial;
  final double? kmFinal;

  /// Pontos de referência ao longo do vão, em ordem crescente de km.
  final List<MarcoPonte> marcos;

  /// `true` quando há escala utilizável pra desenhar o diagrama.
  bool get temEscala =>
      kmInicial != null && kmFinal != null && kmFinal! > kmInicial!;

  List<MarcoPonte> get marcosReferencia =>
      marcos.where((m) => m.tipo == TipoMarcoPonte.referencia).toList();

  List<MarcoPonte> get marcosServico =>
      marcos.where((m) => m.tipo == TipoMarcoPonte.servico).toList();
}

/// Converte uma data no formato ASP.NET (`/Date(1790009659000)/`) que a API
/// usa em todos os campos de horário. Devolve `null` em qualquer formato
/// inesperado — nunca lança.
DateTime? parseDataAspNet(Object? valor) {
  if (valor is! String) return null;
  final m = RegExp(r'/Date\((-?\d+)').firstMatch(valor);
  if (m == null) return null;
  final ms = int.tryParse(m.group(1)!);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Extrai as condições por sentido do JSON já decodificado de
/// `/api/playful-map`.
///
/// Tolerante por princípio (mesmo padrão de `MensagemVoz.fromMap`): é um
/// contrato de terceiro, não documentado e fora do nosso controle — qualquer
/// campo ausente/trocado degrada pra menos informação, nunca lança. Um
/// sentido só entra na lista se tiver ao menos o tempo de travessia.
///
/// Duas fontes são cruzadas dentro do mesmo JSON:
/// - `TravelTimes[]` — uma entrada por sentido, com a cidade de destino e o
///   tempo (`TravelDuration.TotalMinutes`).
/// - `TrafficCondition.Roads[].Conditions[]` — a condição, quebrada em
///   TRECHOS (a Ponte vem dividida em 3 faixas de km por sentido). Como o
///   card mostra um status só por sentido, fica o **pior** trecho daquele
///   sentido (maior `Condition`) — é o que interessa a quem vai atravessar.
CondicoesPonte parseCondicoesPonte(Object? json) {
  if (json is! Map) return const CondicoesPonte(sentidos: []);

  // condição (pior trecho) por cidade de destino, e a lista completa de
  // trechos de cada sentido — o card usa o pior, o diagrama usa todos
  final piorPorSentido = <String, Map<String, Object?>>{};
  final trechosPorSentido = <String, List<TrechoPonte>>{};
  double? kmInicialVia;
  double? kmFinalVia;
  final trafego = json['TrafficCondition'];
  if (trafego is Map) {
    for (final estrada in _lista(trafego['Roads'])) {
      if (estrada is! Map) continue;
      kmInicialVia ??= _decimal(_navegar(estrada, ['Road', 'InitialKM']));
      kmFinalVia ??= _decimal(_navegar(estrada, ['Road', 'FinalKM']));
      for (final cond in _lista(estrada['Conditions'])) {
        if (cond is! Map) continue;
        final nome = _texto(_navegar(cond, ['Direction', 'Name']));
        if (nome == null) continue;
        final nivel = _inteiro(cond['Condition']) ?? 0;
        final atual = piorPorSentido[nome];
        if (atual == null || nivel > (_inteiro(atual['Condition']) ?? 0)) {
          piorPorSentido[nome] = Map<String, Object?>.from(cond);
        }
        final kmIni = _decimal(cond['InitialKM']);
        final kmFim = _decimal(cond['FinalKM']);
        if (kmIni != null && kmFim != null) {
          final motivoTrecho = _texto(cond['Reason']);
          trechosPorSentido.putIfAbsent(nome, () => []).add(TrechoPonte(
                kmInicial: kmIni,
                kmFinal: kmFim,
                nivel: nivel,
                texto: _texto(cond['ConditionText']) ?? '',
                corHex: _texto(cond['ConditionColor']),
                motivo: (motivoTrecho == null || motivoTrecho.isEmpty)
                    ? null
                    : motivoTrecho,
              ));
        }
      }
    }
  }
  for (final lista in trechosPorSentido.values) {
    lista.sort((a, b) => a.kmInicial.compareTo(b.kmInicial));
  }

  // clima por sentido -- a API rotula o trecho em CAIXA ALTA ("NITERÓI"),
  // diferente da cidade de destino ("Niterói"), daí a comparação insensível
  final climaPorSentido = <String, String>{};
  final clima = json['Weather'];
  if (clima is Map) {
    for (final estrada in _lista(clima['Roads'])) {
      if (estrada is! Map) continue;
      for (final trecho in _lista(estrada['Stretches'])) {
        if (trecho is! Map) continue;
        final nome = _texto(trecho['Stretch']);
        final texto = _texto(trecho['ConditionText']);
        if (nome != null && texto != null && texto.isNotEmpty) {
          climaPorSentido[nome.toLowerCase()] = texto;
        }
      }
    }
  }

  final marcos = _extrairMarcos(json);

  final sentidos = <CondicaoPonte>[];
  for (final tt in _lista(json['TravelTimes'])) {
    if (tt is! Map) continue;
    final destino = _texto(_navegar(tt, ['DestinationCity', 'Name']));
    final minutos = _inteiro(_navegar(tt, ['TravelDuration', 'TotalMinutes']));
    if (destino == null || minutos == null) continue;
    final cond = piorPorSentido[destino];
    final motivo = _texto(cond?['Reason']);
    sentidos.add(CondicaoPonte(
      sentido: destino,
      minutos: minutos,
      condicaoTexto: _texto(cond?['ConditionText']) ?? '',
      condicaoNivel: _inteiro(cond?['Condition']) ?? 0,
      corHex: _texto(cond?['ConditionColor']),
      motivo: (motivo == null || motivo.isEmpty) ? null : motivo,
      trechos: trechosPorSentido[destino] ?? const [],
      climaTexto: climaPorSentido[destino.toLowerCase()],
    ));
  }

  return CondicoesPonte(
    sentidos: sentidos,
    atualizadoEm: parseDataAspNet(trafego is Map ? trafego['LastUpdate'] : null),
    kmInicial: kmInicialVia,
    kmFinal: kmFinalVia,
    marcos: marcos,
  );
}

/// Pontos de referência ao longo da Ponte, de duas fontes da MESMA resposta:
///
/// - `Cameras[].Cameras[]` — lugares com nome próprio e km (Vão Central,
///   Grande Curva, Cais do Porto...). São os rótulos verticais do diagrama
///   oficial; usamos a posição das câmeras porque é o único lugar da resposta
///   que nomeia pontos do vão (o site tem esses nomes fixos no próprio SVG).
/// - `RoadInfrastructures[]` — serviços (polícia, SAU, pedágio), marcados por
///   flags `Is*`.
List<MarcoPonte> _extrairMarcos(Map json) {
  final marcos = <MarcoPonte>[];
  final vistos = <String>{};

  for (final grupo in _lista(json['Cameras'])) {
    if (grupo is! Map) continue;
    for (final cam in _lista(grupo['Cameras'])) {
      if (cam is! Map) continue;
      final km = _decimal(cam['KM']);
      final nome = _texto(cam['Description']);
      if (km == null || nome == null || nome.isEmpty) continue;
      if (!vistos.add('r|$nome')) continue;
      marcos.add(MarcoPonte(km: km, nome: nome, tipo: TipoMarcoPonte.referencia));
    }
  }

  for (final ponto in _lista(json['RoadInfrastructures'])) {
    if (ponto is! Map) continue;
    if (ponto['Disabled'] == true) continue;
    final km = _decimal(ponto['KM']);
    final nome = _texto(ponto['Name']);
    if (km == null || nome == null || nome.isEmpty) continue;
    if (!vistos.add('s|$nome')) continue;
    marcos.add(MarcoPonte(km: km, nome: nome, tipo: TipoMarcoPonte.servico));
  }

  marcos.sort((a, b) => a.km.compareTo(b.km));
  return marcos;
}

List<Object?> _lista(Object? v) => v is List ? v : const [];

Object? _navegar(Map origem, List<String> caminho) {
  Object? atual = origem;
  for (final chave in caminho) {
    if (atual is! Map) return null;
    atual = atual[chave];
  }
  return atual;
}

String? _texto(Object? v) => v is String ? v.trim() : null;

double? _decimal(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _inteiro(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}
