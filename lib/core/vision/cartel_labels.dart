const Set<String> kCartelLabelSet = {
  'anuncios informativos',
  'anuncios publicitarios',
  'carteles de comida',
  'carteles direccion',
  'carteles de precio',
  'letrero',
  'letrero calle',
  'letrero direccion',
  'letrero informativo',
  'letrero tienda',
  'letrero vial',
  'numeracion de calle',
  'placa calle',
  'publicidad',
  'publicidad de comida',
  'rotulo',
  'señal informativa',
  'señal vial',
};

const List<String> _kCartelKeywords = <String>[
  'cartel',
  'letrero',
  'aviso',
  'anuncio',
  'publicidad',
  'rótulo',
  'rotulo',
  'señal',
  'senal',
  'calle',
  'avenida',
  'dirección',
  'direccion',
  'street',
  'price',
];

bool isCartelLabel(String? label) {
  if (label == null) return false;
  final normalized = label.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  if (kCartelLabelSet.contains(normalized)) {
    return true;
  }
  for (final keyword in _kCartelKeywords) {
    if (normalized.contains(keyword)) {
      return true;
    }
  }
  return false;
}
