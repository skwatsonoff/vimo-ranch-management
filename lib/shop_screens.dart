part of 'main.dart';

// =============================================================================
//  Shop screens: list a product, see a product, buy it, and follow orders.
// =============================================================================

Widget _shopSection(String title, {String? note}) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
      ),
      if (note != null) ...[
        const SizedBox(height: 2),
        Text(note, style: TextStyle(color: Ink.muted, fontSize: 13)),
      ],
    ],
  ),
);

ImageProvider? _shopImage(String data) => cachedPhoto(data);

/// A choice row of capsules (single or several).
class _ChoiceChips extends StatelessWidget {
  final List<ShopChoice> choices;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  const _ChoiceChips({
    required this.choices,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in choices)
        ChoiceChip(
          label: Text(bi(c.$2, c.$3)),
          selected: selected.contains(c.$1),
          showCheckmark: false,
          selectedColor: Ink.tint,
          labelStyle: TextStyle(
            color: selected.contains(c.$1) ? Colors.white : Ink.navy,
            fontWeight: FontWeight.w600,
          ),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) {
            selectionFeedback();
            onTap(c.$1);
          },
        ),
    ],
  );
}

// -----------------------------------------------------------------------------
//  List or edit a product
// -----------------------------------------------------------------------------

class ProductEditorScreen extends StatefulWidget {
  final String? productId;
  final Map<String, dynamic>? product;
  final Map<String, dynamic>? draft;
  const ProductEditorScreen({
    super.key,
    this.productId,
    this.product,
    this.draft,
  });

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  late final Map<String, dynamic> _p =
      widget.product ?? asMap(widget.draft?['product']);
  late final String _uid = signedInUid;
  late final String _id =
      widget.productId ??
      widget.draft?['id'] as String? ??
      ShopService.newProductId();
  late final _title = TextEditingController(text: txt(_p, 'title'));
  late final _description = TextEditingController(text: txt(_p, 'description'));
  late final List<TextEditingController> _features = [
    for (final f in (_p['features'] as List?) ?? const [])
      TextEditingController(text: '$f'),
  ];
  late final _price = TextEditingController(
    text: _p['price'] == null ? '' : vendorFieldNumber(numv(_p, 'price')),
  );
  late final _mrp = TextEditingController(
    text: numv(_p, 'mrp') > 0 ? vendorFieldNumber(numv(_p, 'mrp')) : '',
  );
  late final _unitSize = TextEditingController(text: txt(_p, 'unitSize'));
  late final _stock = TextEditingController(
    text: _p['stock'] == null ? '1' : '${toInt(_p['stock'])}',
  );
  late final _maxPerOrder = TextEditingController(
    text: toInt(_p['maxPerOrder']) > 1 ? '${toInt(_p['maxPerOrder'])}' : '',
  );

  /// One per order (a cow, a used phone) unless the seller lets buyers
  /// choose how many (milk packets, ghee jars).
  late bool _single =
      _p['maxPerOrder'] == null || toInt(_p['maxPerOrder']) <= 1;
  late final _fee = TextEditingController(
    text: numv(asMap(_p['delivery']), 'fee') > 0
        ? vendorFieldNumber(numv(asMap(_p['delivery']), 'fee'))
        : '',
  );
  late final _shipsFrom = TextEditingController(
    text: txt(
      asMap(_p['delivery']),
      'shipsFrom',
      txt(accountDetails, 'place', placeName()),
    ),
  );
  late final _tag = TextEditingController();
  late final _brand = TextEditingController(text: txt(_p, 'brand'));
  late final _sku = TextEditingController(text: txt(_p, 'sku'));
  late final _weight = TextEditingController(
    text: toInt(_p['weightGrams']) > 0 ? '${toInt(_p['weightGrams'])}' : '',
  );
  late final _origin = TextEditingController(text: txt(_p, 'origin', 'India'));
  late final _manufacturer = TextEditingController(
    text: txt(_p, 'manufacturer'),
  );
  late final _hsn = TextEditingController(text: txt(_p, 'hsn'));

  late String _category = txt(_p, 'category', 'dairy');
  late String _condition = txt(_p, 'condition', 'new');
  late String _unit = txt(_p, 'unit', 'piece');
  late String? _method = _savedMethod();

  String? _savedMethod() {
    final methods = asMap(_p['delivery'])['methods'];
    if (methods is! List || methods.length != 1) return null;
    return shopDeliveryMethods.any((method) => method.$1 == methods.single)
        ? methods.single as String
        : null;
  }

  late String _payer = txt(asMap(_p['delivery']), 'payer', 'seller');
  late String _days = txt(asMap(_p['delivery']), 'days', '1-2');
  late String _returns = txt(_p, 'returns', 'none');
  late int _gst = toInt(_p['gstPercent']);
  late final List<String> _tags = [
    for (final t in (_p['tags'] as List?) ?? const []) '$t',
  ];

  /// Taken down by the VIMO Team: stays hidden until the team allows it.
  late final bool _takenDown = _p['pausedByTeam'] == true;
  late bool _listed = !_takenDown && txt(_p, 'status', 'active') == 'active';

  List<String> _photos = [];
  bool _loadingPhotos = false;
  bool _photoLoadFailed = false;
  bool _picking = false;
  bool _saving = false;
  bool _more = false;

  bool get _editing => widget.productId != null;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      for (final entry in _draftFields.entries) {
        entry.value.text = txt(asMap(draft['text']), entry.key);
      }
      for (final value in (draft['features'] as List?) ?? const []) {
        _features.add(TextEditingController(text: '$value'));
      }
      _category = txt(draft, 'category', _category);
      _condition = txt(draft, 'condition', _condition);
      _unit = txt(draft, 'unit', _unit);
      _method = draft['method'] as String?;
      _payer = txt(draft, 'payer', _payer);
      _days = txt(draft, 'days', _days);
      _returns = txt(draft, 'returns', _returns);
      _gst = toInt(draft['gst']);
      _single = draft['single'] == true;
      _listed = !_takenDown && draft['listed'] == true;
      _tags
        ..clear()
        ..addAll(((draft['tags'] as List?) ?? const []).whereType<String>());
      _more = draft['more'] == true;
    }
    final draftPhotos = draft?['photos'];
    if (draftPhotos is List) {
      _photos = draftPhotos.whereType<String>().toList();
    } else if (_editing) {
      _loadPhotos();
    }
    if (_features.isEmpty) _features.add(TextEditingController());
  }

  Map<String, TextEditingController> get _draftFields => {
    'title': _title,
    'description': _description,
    'price': _price,
    'mrp': _mrp,
    'unitSize': _unitSize,
    'stock': _stock,
    'maxPerOrder': _maxPerOrder,
    'fee': _fee,
    'shipsFrom': _shipsFrom,
    'tag': _tag,
    'brand': _brand,
    'sku': _sku,
    'weight': _weight,
    'origin': _origin,
    'manufacturer': _manufacturer,
    'hsn': _hsn,
  };

  Future<void> _storeDraft() {
    if (_uid.isEmpty || signedInUid != _uid) {
      throw StateError(
        bi('Sign in to save your draft', 'வரைவைச் சேமிக்க உள்நுழையவும்'),
      );
    }
    return ShopDrafts.save(_uid, _id, {
      if (_editing)
        'product': {
          'photoCount': toInt(_p['photoCount']),
          'pausedByTeam': _takenDown,
        },
      'text': {
        for (final entry in _draftFields.entries) entry.key: entry.value.text,
      },
      'features': [for (final feature in _features) feature.text],
      'photos': _loadingPhotos || _photoLoadFailed
          ? null
          : List<String>.of(_photos),
      'category': _category,
      'condition': _condition,
      'unit': _unit,
      'method': _method,
      'payer': _payer,
      'days': _days,
      'returns': _returns,
      'gst': _gst,
      'single': _single,
      'listed': _listed,
      'tags': List<String>.of(_tags),
      'more': _more,
    });
  }

  String get _draftSaved => bi(
    'Draft saved on this device.',
    'வரைவு இந்தச் சாதனத்தில் சேமிக்கப்பட்டது.',
  );

  Future<void> _saveDraft() async {
    if (_saving || _picking) return;
    setState(() => _saving = true);
    try {
      await _storeDraft();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      snack(
        context,
        _draftSaved,
        tone: SnackTone.success,
        messenger: messenger,
      );
    } catch (_) {
      if (mounted) {
        snack(
          context,
          bi(
            'Could not save the draft. Keep this screen open and try again.',
            'வரைவைச் சேமிக்க முடியவில்லை. இந்தத் திரையைத் திறந்தபடியே மீண்டும் முயலவும்.',
          ),
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _loadingPhotos = true;
      _photoLoadFailed = false;
    });
    try {
      final photos = await ShopService.photos(
        widget.productId!,
        toInt(_p['photoCount']),
      );
      if (photos.length != toInt(_p['photoCount'])) {
        throw StateError('Missing photos');
      }
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
      if (mounted) setState(() => _photoLoadFailed = true);
    } finally {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  @override
  void dispose() {
    for (final c in [..._draftFields.values, ..._features]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_saving ||
        _loadingPhotos ||
        _photoLoadFailed ||
        _picking ||
        _photos.length >= 5) {
      return;
    }
    setState(() => _picking = true);
    try {
      final picked = await pickImageDataUrl(social: true);
      if (picked == null) return;
      final photo = await productPhotoFrom(picked);
      if (photo == null) throw StateError('photo');
      if (mounted) setState(() => _photos.add(photo));
    } catch (_) {
      if (mounted) {
        snack(
          context,
          bi(
            'Could not use that photo',
            'அந்தப் படத்தைப் பயன்படுத்த முடியவில்லை',
          ),
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _photoActions(int index) async {
    final choice = await showAppleSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index > 0)
                LiquidButton(
                  label: bi('Make cover photo', 'முதன்மைப் படமாக்கு'),
                  icon: CupertinoIcons.star_fill,
                  onPressed: () => Navigator.pop(sheet, 'cover'),
                ),
              const SizedBox(height: 8),
              GhostButton(
                label: bi('Remove photo', 'படத்தை நீக்கு'),
                icon: CupertinoIcons.trash,
                color: Ink.redText,
                onPressed: () => Navigator.pop(sheet, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      final photo = _photos.removeAt(index);
      if (choice == 'cover') _photos.insert(0, photo);
    });
  }

  void _addTag() {
    final tag = shopTag(_tag.text);
    if (tag.isEmpty || _tags.length >= 5 || _tags.contains(tag)) {
      _tag.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tag.clear();
    });
  }

  String? _problem() {
    final price = double.tryParse(_price.text.trim());
    final mrp = _mrp.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_mrp.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    final most = int.tryParse(_maxPerOrder.text.trim());
    final fee =
        _method == 'pickup' || _payer != 'buyer' || _fee.text.trim().isEmpty
        ? 0.0
        : double.tryParse(_fee.text.trim());
    final weight = _weight.text.trim().isEmpty
        ? 0
        : int.tryParse(_weight.text.trim());
    if (_photoLoadFailed || _loadingPhotos) {
      return bi(
        'Load the existing photos before publishing',
        'பதிவிடுவதற்கு முன் பழைய படங்களை ஏற்றவும்',
      );
    }
    if (_photos.isEmpty) {
      return bi('Add at least one photo', 'குறைந்தது ஒரு படம் சேர்க்கவும்');
    }
    if (_title.text.trim().length < 3) {
      return bi('Write a title (3 letters or more)', 'தலைப்பை எழுதவும்');
    }
    if (price == null || !price.isFinite || price <= 0 || price > 10000000) {
      return bi('Enter a price', 'விலையை உள்ளிடவும்');
    }
    if (mrp == null || !mrp.isFinite || (mrp != 0 && mrp < price)) {
      return bi(
        'MRP must be the same as or more than the price',
        'MRP விலைக்குச் சமம் அல்லது அதிகமாக இருக்க வேண்டும்',
      );
    }
    if (stock == null || stock < 0 || stock > 100000) {
      return bi('Enter how many you have', 'கையிருப்பு எண்ணிக்கையை உள்ளிடவும்');
    }
    if (!_single && (most == null || most < 2 || most > 100000)) {
      return bi(
        'Enter how many one buyer can order (2 or more)',
        'ஒருவர் எத்தனை ஆர்டர் செய்யலாம் என்பதை உள்ளிடவும் (2 அல்லது அதிகம்)',
      );
    }
    if (_method == null) {
      return bi(
        'Choose how buyers get it',
        'எப்படிக் கிடைக்கும் என்பதைத் தேர்வு செய்யவும்',
      );
    }
    if (fee == null || !fee.isFinite || fee < 0 || fee > 100000) {
      return bi(
        'Enter a valid delivery fee',
        'சரியான டெலிவரி கட்டணத்தை உள்ளிடவும்',
      );
    }
    if (weight == null || weight < 0 || weight > 1000000) {
      return bi(
        'Enter a weight from 0 to 1,000,000 grams',
        '0 முதல் 10,00,000 கிராம் வரை எடையை உள்ளிடவும்',
      );
    }
    if (_hsn.text.trim().isNotEmpty &&
        !RegExp(r'^[0-9]{4,8}$').hasMatch(_hsn.text.trim())) {
      return bi('HSN code is 4 to 8 digits', 'HSN குறியீடு 4–8 எண்கள்');
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || _picking) return;
    setState(() => _saving = true);
    var draftStored = false;
    try {
      await _storeDraft();
      draftStored = true;
      if (!mounted) return;
      final problem = _problem();
      if (problem != null) {
        snack(context, '$problem. $_draftSaved', tone: SnackTone.error);
        return;
      }
      final features = [
        for (final f in _features)
          if (f.text.trim().isNotEmpty)
            f.text.trim().length > 100
                ? f.text.trim().substring(0, 100)
                : f.text.trim(),
      ].take(5).toList();
      final title = _title.text.trim();
      final brand = _brand.text.trim();
      // Lock the form before prompting for location or checking the account.
      if (!await MarketLocation.require(context) || !mounted) return;
      if (!await VimoTeam.marketAllowed(context) || !mounted) return;
      final id = await ShopService.save(
        id: _id,
        uid: _uid,
        editing: _editing,
        photos: _photos,
        fields: {
          'title': title,
          'description': _description.text.trim(),
          'features': features,
          'category': _category,
          'condition': _condition,
          'brand': brand,
          'tags': _tags,
          'searchTerms': shopSearchTerms(
            title: title,
            tags: _tags,
            brand: brand,
            category: _category,
          ),
          'price': double.parse(_price.text.trim()),
          'mrp': _mrp.text.trim().isEmpty ? 0.0 : double.parse(_mrp.text),
          'unit': _unit,
          'unitSize': _unitSize.text.trim(),
          'stock': int.parse(_stock.text.trim()),
          'maxPerOrder': _single ? 1 : int.parse(_maxPerOrder.text.trim()),
          'sku': _sku.text.trim(),
          'weightGrams': int.tryParse(_weight.text.trim()) ?? 0,
          'origin': _origin.text.trim(),
          'manufacturer': _manufacturer.text.trim(),
          'gstPercent': _gst,
          'hsn': _hsn.text.trim(),
          'delivery': {
            'methods': [_method!],
            'payer': _method == 'pickup' ? 'seller' : _payer,
            'fee':
                _method != 'pickup' &&
                    _payer == 'buyer' &&
                    _fee.text.trim().isNotEmpty
                ? double.parse(_fee.text.trim())
                : 0.0,
            'days': _days,
            'shipsFrom': _shipsFrom.text.trim(),
          },
          'returns': _returns,
          'status': _listed && !_takenDown ? 'active' : 'paused',
        },
      );
      // A local cleanup failure must never report a successful publish as failed.
      await ShopDrafts.remove(_uid, _id).catchError((Object _) {});
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(id);
      snack(
        context,
        _editing
            ? bi('Product updated', 'பொருள் புதுப்பிக்கப்பட்டது')
            : bi('Product listed', 'பொருள் பட்டியலிடப்பட்டது'),
        tone: SnackTone.success,
        messenger: messenger,
      );
    } catch (error) {
      if (mounted) {
        snack(
          context,
          !draftStored
              ? (error is StateError
                    ? error.message
                    : bi(
                        'Could not save the draft. Keep this screen open and try again.',
                        'வரைவைச் சேமிக்க முடியவில்லை. இந்தத் திரையைத் திறந்தபடியே மீண்டும் முயலவும்.',
                      ))
              : '${error is StateError ? error.message : bi('Could not publish. Check your connection and try again from Drafts.', 'பதிவிட முடியவில்லை. இணையத்தைச் சரிபார்த்து வரைவுகளிலிருந்து மீண்டும் முயலவும்.')} $_draftSaved',
          tone: SnackTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppleAlert(
        title: Text(bi('Delete this product?', 'இந்தப் பொருளை நீக்கவா?')),
        content: Text(
          bi(
            'It leaves your shop. Orders already placed keep their details.',
            'உங்கள் கடையிலிருந்து நீங்கும். ஏற்கனவே வந்த ஆர்டர்களின் விவரம் இருக்கும்.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ui('Cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Ink.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bi('Delete', 'நீக்கு')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await ShopService.delete(widget.productId!, toInt(_p['photoCount']));
      await ShopDrafts.remove(_uid, _id).catchError((Object _) {});
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop('deleted');
      snack(
        context,
        bi('Product deleted', 'பொருள் நீக்கப்பட்டது'),
        tone: SnackTone.success,
        messenger: messenger,
      );
    } catch (error) {
      if (mounted) snack(context, accountError(error), tone: SnackTone.error);
    }
  }

  Widget _photoStrip() => SizedBox(
    height: 104,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < _photos.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Semantics(
              button: true,
              label: i == 0
                  ? bi('Cover photo', 'முதன்மைப் படம்')
                  : bi('Photo ${i + 1}', 'படம் ${i + 1}'),
              child: Pressable(
                radius: 18,
                onTap: () => _photoActions(i),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image(
                        image: _shopImage(_photos[i])!,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: Colors.black.withValues(alpha: .6),
                          ),
                          child: Text(
                            bi('Cover', 'முதன்மை'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_photos.length < 5)
          Semantics(
            button: true,
            label: bi('Add photo', 'படம் சேர்'),
            child: Pressable(
              radius: 18,
              onTap: _addPhoto,
              child: Container(
                width: 104,
                height: 104,
                decoration: ShapeDecoration(
                  shape: const SquircleBorder(radius: 18),
                  color: Ink.lavender,
                ),
                child: _picking || _loadingPhotos
                    ? const Center(child: CupertinoActivityIndicator())
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.camera_fill,
                            color: Ink.violetDeep,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_photos.length}/5',
                            style: TextStyle(
                              color: Ink.violetDeep,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final mrp = double.tryParse(_mrp.text.trim()) ?? 0;
    final off = shopDiscount(price, mrp);
    final deliveryOnly = _method != null && _method != 'pickup';
    return Scaffold(
      backgroundColor: Ink.canvasTop,
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(
          _editing
              ? bi('Edit product', 'பொருளைத் திருத்து')
              : bi('List a product', 'பொருளைப் பட்டியலிடு'),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _picking ? null : _saveDraft,
            child: Text(
              bi('Save draft', 'வரைவைச் சேமி'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Shell(
        absorbing: _saving,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            _shopSection(
              bi('Photos', 'படங்கள்'),
              note: bi(
                '1 to 5 photos. The first is the cover buyers see first.',
                '1 முதல் 5 படங்கள். முதல் படம் வாங்குபவர்கள் முதலில் பார்ப்பது.',
              ),
            ),
            _photoStrip(),
            if (_photoLoadFailed)
              TextButton(
                onPressed: _loadPhotos,
                child: Text(
                  bi('Retry loading photos', 'படங்களை மீண்டும் ஏற்று'),
                ),
              ),
            _shopSection(bi('About the product', 'பொருள் பற்றி')),
            TextField(
              controller: _title,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldStyle(bi('Title', 'தலைப்பு')),
            ),
            const SizedBox(height: 4),
            PickerField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: fieldStyle(bi('Category', 'வகை')),
              items: [
                for (final c in shopCategories)
                  DropdownMenuItem(value: c.$1, child: Text(bi(c.$2, c.$3))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            Text(
              bi('Condition', 'நிலை'),
              style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _ChoiceChips(
              choices: shopConditions,
              selected: {_condition},
              onTap: (v) => setState(() => _condition = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              maxLength: 2000,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldStyle(bi('Description', 'விவரம்')),
            ),
            Text(
              bi('Key features (up to 5)', 'முக்கிய அம்சங்கள் (5 வரை)'),
              style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _features.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _features[i],
                  maxLength: 100,
                  decoration:
                      fieldStyle(
                        '',
                        icon: CupertinoIcons.checkmark_circle,
                      ).copyWith(
                        hintText: bi(
                          'e.g. Fresh A2 milk, packed today',
                          'எ.கா. இன்று பேக் செய்த A2 பால்',
                        ),
                        counterText: '',
                      ),
                ),
              ),
            if (_features.length < 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _features.add(TextEditingController())),
                  icon: const Icon(CupertinoIcons.add),
                  label: Text(bi('Add a feature', 'அம்சம் சேர்')),
                ),
              ),
            _shopSection(bi('Price & stock', 'விலை & கையிருப்பு')),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: fieldStyle(
                      bi('Price', 'விலை'),
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(currencySymbol()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mrp,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: fieldStyle(
                      bi('MRP (optional)', 'MRP (விருப்பம்)'),
                      prefix: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(currencySymbol()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (off > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  bi(
                    'Buyers see $off% off',
                    'வாங்குபவர்கள் $off% தள்ளுபடி காண்பார்கள்',
                  ),
                  style: TextStyle(
                    color: Ink.greenText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PickerField<String>(
                    initialValue: _unit,
                    isExpanded: true,
                    decoration: fieldStyle(bi('Sold per', 'விற்கும் அலகு')),
                    items: [
                      for (final u in productUnits)
                        DropdownMenuItem(
                          value: u.$1,
                          child: Text(bi(u.$2, u.$3)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? _unit),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unitSize,
                    maxLength: 20,
                    decoration: fieldStyle(
                      bi('Pack size', 'பேக் அளவு'),
                    ).copyWith(hintText: '1 L, 500 g…', counterText: ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: fieldStyle(
                bi('Quantity in stock', 'கையிருப்பு எண்ணிக்கை'),
                icon: CupertinoIcons.cube_box,
              ),
            ),
            const SizedBox(height: 12),
            // The seller decides whether one order can take several.
            LiquidSegmentBar(
              labels: [
                bi('One per order', 'ஆர்டருக்கு ஒன்று'),
                bi('Buyer chooses how many', 'எத்தனை என வாங்குபவர் தேர்வு'),
              ],
              index: _single ? 0 : 1,
              onChanged: (v) => setState(() {
                _single = v == 0;
                if (!_single && _maxPerOrder.text.trim().isEmpty) {
                  _maxPerOrder.text = _stock.text.trim();
                }
              }),
            ),
            if (!_single) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _maxPerOrder,
                keyboardType: TextInputType.number,
                decoration: fieldStyle(
                  bi('Most in one order', 'ஒரு ஆர்டரில் அதிகபட்சம்'),
                  icon: CupertinoIcons.number,
                ),
              ),
            ],
            _shopSection(
              bi('Delivery', 'டெலிவரி'),
              note: bi(
                'Choose one delivery method.',
                'ஒரு டெலிவரி முறையைத் தேர்வு செய்யவும்.',
              ),
            ),
            _ChoiceChips(
              choices: shopDeliveryMethods,
              selected: {?_method},
              onTap: (value) => setState(() => _method = value),
            ),
            if (deliveryOnly) ...[
              const SizedBox(height: 16),
              LiquidSegmentBar(
                labels: [
                  bi('Free delivery', 'இலவச டெலிவரி'),
                  bi('Buyer pays delivery', 'வாங்குபவர் கட்டணம்'),
                ],
                index: _payer == 'buyer' ? 1 : 0,
                onChanged: (v) =>
                    setState(() => _payer = v == 1 ? 'buyer' : 'seller'),
              ),
              if (_payer == 'buyer') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _fee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: fieldStyle(
                    bi('Delivery fee', 'டெலிவரி கட்டணம்'),
                    prefix: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(currencySymbol()),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                bi('Sends within', 'அனுப்பும் காலம்'),
                style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _ChoiceChips(
                choices: shopShipDays,
                selected: {_days},
                onTap: (v) => setState(() => _days = v),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _shipsFrom,
              maxLength: 80,
              decoration: fieldStyle(
                bi('From (town / area)', 'இருந்து (ஊர் / பகுதி)'),
                icon: CupertinoIcons.location,
              ),
            ),
            Text(
              bi('Returns', 'திருப்பி அனுப்புதல்'),
              style: TextStyle(color: Ink.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _ChoiceChips(
              choices: shopReturns,
              selected: {_returns},
              onTap: (v) => setState(() => _returns = v),
            ),
            _shopSection(
              bi('Search tags', 'தேடல் குறிச்சொற்கள்'),
              note: bi(
                'Up to 5 words that help people find this in Market. They are not shown on the item page.',
                'சந்தையில் இதைக் கண்டறிய உதவும் 5 சொற்கள் வரை. பொருள் பக்கத்தில் காட்டப்படாது.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: () => setState(() => _tags.remove(t)),
                    deleteButtonTooltipMessage: bi('Remove', 'நீக்கு'),
                  ),
              ],
            ),
            if (_tags.length < 5) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _tag,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTag(),
                decoration:
                    fieldStyle(
                      bi('Add a tag', 'குறிச்சொல் சேர்'),
                      icon: CupertinoIcons.tag,
                      suffix: IconButton(
                        tooltip: bi('Add', 'சேர்'),
                        icon: const Icon(CupertinoIcons.add_circled_solid),
                        onPressed: _addTag,
                      ),
                    ).copyWith(
                      hintText: bi(
                        'e.g. a2, organic, desi',
                        'எ.கா. a2, இயற்கை',
                      ),
                    ),
              ),
            ],
            const SizedBox(height: 8),
            // Details Amazon and Meesho ask for, one step deeper.
            Glass(
              radius: 20,
              padding: EdgeInsets.zero,
              // Its own Material so the row's press highlight shows on the
              // card.
              child: Material(
                type: MaterialType.transparency,
                child: Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: _more,
                    onExpansionChanged: (v) => _more = v,
                    title: Text(
                      bi('More details', 'கூடுதல் விவரங்கள்'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      bi(
                        'Brand, SKU, weight, origin, maker, GST and HSN',
                        'பிராண்ட், SKU, எடை, நாடு, தயாரிப்பாளர், GST, HSN',
                      ),
                      style: TextStyle(color: Ink.muted, fontSize: 13),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _brand,
                        maxLength: 60,
                        decoration: fieldStyle(bi('Brand', 'பிராண்ட்')),
                      ),
                      TextField(
                        controller: _sku,
                        maxLength: 40,
                        decoration: fieldStyle(
                          bi('SKU / item code', 'SKU / பொருள் குறியீடு'),
                        ),
                      ),
                      TextField(
                        controller: _weight,
                        keyboardType: TextInputType.number,
                        decoration: fieldStyle(
                          bi(
                            'Weight with packing (grams)',
                            'பேக்கிங்குடன் எடை (கிராம்)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _origin,
                        maxLength: 40,
                        decoration: fieldStyle(
                          bi('Country of origin', 'தயாரிப்பு நாடு'),
                        ),
                      ),
                      TextField(
                        controller: _manufacturer,
                        maxLength: 120,
                        decoration: fieldStyle(
                          bi(
                            'Manufacturer / packer',
                            'தயாரிப்பாளர் / பேக் செய்பவர்',
                          ),
                        ),
                      ),
                      Text(
                        bi('GST', 'GST'),
                        style: TextStyle(
                          color: Ink.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ChoiceChips(
                        choices: [
                          for (final r in shopGstRates) ('$r', '$r%', '$r%'),
                        ],
                        selected: {'$_gst'},
                        onTap: (v) => setState(() => _gst = int.parse(v)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _hsn,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        decoration: fieldStyle(
                          bi('HSN code (optional)', 'HSN குறியீடு (விருப்பம்)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _InsetGroup(
              children: [
                SoundSwitchListTile(
                  value: _listed,
                  onChanged: _takenDown
                      ? null
                      : (v) => setState(() => _listed = v),
                  title: Text(bi('Show in my shop', 'என் கடையில் காட்டு')),
                  subtitle: Text(
                    _takenDown
                        ? bi(
                            'Taken down by VIMO Team. Open My orders → Help to talk to them.',
                            'VIMO Team நீக்கியது. பேச என் ஆர்டர்கள் → உதவி திறக்கவும்.',
                          )
                        : bi(
                            'Turn off to pause without deleting.',
                            'நீக்காமல் நிறுத்த அணைக்கவும்.',
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LiquidButton(
              label: _editing
                  ? bi('Save changes', 'மாற்றங்களைச் சேமி')
                  : bi('List product', 'பொருளைப் பட்டியலிடு'),
              icon: CupertinoIcons.checkmark_alt,
              busy: _saving,
              onPressed: _picking ? null : _save,
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: bi('Save draft', 'வரைவைச் சேமி'),
              icon: CupertinoIcons.doc,
              onPressed: _saving || _picking ? null : _saveDraft,
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              GhostButton(
                label: bi('Delete product', 'பொருளை நீக்கு'),
                icon: CupertinoIcons.trash,
                color: Ink.redText,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
//  Product cards and the shop grid
// -----------------------------------------------------------------------------

/// A product tile: cover photo, title, price (and MRP struck through).
class ProductTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> product;
  const ProductTile({super.key, required this.id, required this.product});

  @override
  Widget build(BuildContext context) {
    final price = numv(product, 'price');
    final mrp = numv(product, 'mrp');
    final off = shopDiscount(price, mrp);
    final paused = txt(product, 'status') != 'active';
    final out = toInt(product['stock']) <= 0;
    return Semantics(
      button: true,
      label: '${txt(product, 'title')}, ${money(price)}',
      excludeSemantics: true,
      child: Glass(
        radius: 20,
        padding: EdgeInsets.zero,
        onTap: () => push(context, ProductScreen(id: id, initial: product)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_shopImage(txt(product, 'cover')) case final image?)
                      Image(image: image, fit: BoxFit.cover)
                    else
                      ColoredBox(color: Ink.lavender),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: LikeButton(
                        productId: id,
                        product: product,
                        small: true,
                      ),
                    ),
                    if (paused || out)
                      ColoredBox(
                        color: Colors.black.withValues(alpha: .45),
                        child: Center(
                          child: Text(
                            paused
                                ? bi('Paused', 'நிறுத்தப்பட்டது')
                                : bi('Sold out', 'விற்றுத் தீர்ந்தது'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txt(product, 'title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        money(price),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (off > 0) ...[
                        Text(
                          money(mrp),
                          style: TextStyle(
                            color: Ink.muted,
                            decoration: TextDecoration.lineThrough,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '$off% ${bi('off', 'தள்ளுபடி')}',
                          style: TextStyle(
                            color: Ink.greenText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A two-column grid of product tiles that grows with the screen.
class ProductGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const ProductGrid({super.key, required this.docs});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 600 ? 3 : 2;
      final width = (c.maxWidth - 12 * (columns - 1)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final d in docs)
            SizedBox(
              width: width,
              child: ProductTile(id: d.id, product: d.data()),
            ),
        ],
      );
    },
  );
}

/// The shop on a profile: products, and for the owner a pencil to add one.
class ShopDraftsScreen extends StatelessWidget {
  const ShopDraftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = signedInUid;
    return Scaffold(
      appBar: AppBar(
        leading: const _BackButton(),
        title: Text(bi('Product drafts', 'பொருள் வரைவுகள்')),
      ),
      body: Shell(
        child: ValueListenableBuilder<Box>(
          valueListenable: Hive.box(ShopDrafts.boxName).listenable(),
          builder: (context, box, _) {
            final drafts = ShopDrafts.forUser(uid);
            if (drafts.isEmpty) {
              return Center(
                child: Text(
                  bi(
                    'No drafts on this device',
                    'இந்தச் சாதனத்தில் வரைவுகள் இல்லை',
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                final id = txt(draft, 'id');
                final title = txt(asMap(draft['text']), 'title').trim();
                return ListTile(
                  leading: const Icon(CupertinoIcons.doc),
                  title: Text(
                    title.isEmpty
                        ? bi('Untitled product', 'தலைப்பில்லாத பொருள்')
                        : title,
                  ),
                  subtitle: Text(
                    bi(
                      'Tap to edit or publish',
                      'திருத்த அல்லது பட்டியலிடத் தொடவும்',
                    ),
                  ),
                  onTap: () => push(
                    context,
                    ProductEditorScreen(
                      productId: draft['product'] is Map ? id : null,
                      draft: draft,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.trash),
                    tooltip: bi('Delete draft', 'வரைவை நீக்கு'),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AppleAlert(
                          title: Text(
                            bi('Delete this draft?', 'இந்த வரைவை நீக்கவா?'),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: Text(ui('Cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: Text(bi('Delete draft', 'வரைவை நீக்கு')),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await ShopDrafts.remove(uid, id);
                        } catch (_) {
                          if (context.mounted) {
                            snack(
                              context,
                              bi(
                                'Could not delete the draft',
                                'வரைவை நீக்க முடியவில்லை',
                              ),
                              tone: SnackTone.error,
                            );
                          }
                        }
                      }
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ProfileShop extends StatelessWidget {
  final String uid;
  final bool own;
  final Map<String, dynamic> profile;
  const ProfileShop({
    super.key,
    required this.uid,
    required this.own,
    required this.profile,
  });

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: ShopService.productsOf(uid),
    builder: (context, snap) {
      final docs =
          [
            for (final d
                in snap.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              if (own || txt(d.data(), 'status') == 'active') d,
          ]..sort(
            (a, b) => (_marketTime(b.data()['updatedAt']) ?? DateTime(2000))
                .compareTo(
                  _marketTime(a.data()['updatedAt']) ?? DateTime(2000),
                ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (txt(profile, 'shopName').isNotEmpty ||
              txt(profile, 'shopDetails').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (txt(profile, 'shopName').isNotEmpty)
                    Text(
                      txt(profile, 'shopName'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (txt(profile, 'shopDetails').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(txt(profile, 'shopDetails')),
                  ],
                ],
              ),
            ),
          if (snap.hasError)
            Text(accountError(snap.error!))
          else if (!snap.hasData)
            const SkeletonList(rows: 2, padding: EdgeInsets.zero)
          else if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                own
                    ? bi(
                        'Nothing listed yet. Tap the pencil to add your first product.',
                        'இன்னும் எதுவும் இல்லை. முதல் பொருளைச் சேர்க்க பென்சிலைத் தொடவும்.',
                      )
                    : bi('No products yet.', 'இன்னும் பொருட்கள் இல்லை.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Ink.muted),
              ),
            )
          else
            ProductGrid(docs: docs),
          if (own) ...[
            const SizedBox(height: 20),
            Center(
              child: Semantics(
                button: true,
                label: bi('Add a product', 'பொருள் சேர்'),
                child: FloatingActionButton.extended(
                  heroTag: 'add-product',
                  backgroundColor: Ink.tint,
                  foregroundColor: Colors.white,
                  onPressed: () => push(context, const ProductEditorScreen()),
                  icon: const Icon(CupertinoIcons.pencil),
                  label: Text(bi('Add product', 'பொருள் சேர்')),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => push(context, const ShopDraftsScreen()),
                icon: const Icon(CupertinoIcons.doc_on_doc),
                label: Text(bi('Product drafts', 'பொருள் வரைவுகள்')),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: () =>
                    push(context, const OrdersScreen(selling: true)),
                icon: const Icon(CupertinoIcons.doc_text),
                label: Text(bi('Orders for my shop', 'என் கடை ஆர்டர்கள்')),
              ),
            ),
          ],
        ],
      );
    },
  );
}
