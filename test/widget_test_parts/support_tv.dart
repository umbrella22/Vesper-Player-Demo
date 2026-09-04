part of '../widget_test.dart';

final class _FakeTvHomeClient extends BiliClient {
  factory _FakeTvHomeClient({
    List<BiliFeedVideo>? feedItems,
    List<BiliSearchResult>? searchResults,
    bool emptyFollowing = false,
  }) {
    final libraryHttpClient = _FakeTvHomeLibraryHttpClient(
      emptyFollowing: emptyFollowing,
    );
    return _FakeTvHomeClient._(
      libraryHttpClient,
      feedItems: feedItems,
      searchResults: searchResults,
    );
  }

  _FakeTvHomeClient._(
    this.libraryHttpClient, {
    List<BiliFeedVideo>? feedItems,
    List<BiliSearchResult>? searchResults,
  }) : feedItems = feedItems ?? _tvFeedItems(),
       searchResults = searchResults ?? const <BiliSearchResult>[],
       super(httpClient: libraryHttpClient);

  final List<BiliFeedVideo> feedItems;
  final List<BiliSearchResult> searchResults;
  final _FakeTvHomeLibraryHttpClient libraryHttpClient;
  final List<BiliRegionSection> requestedSections = <BiliRegionSection>[];
  final List<String> requestedVideoDetails = <String>[];
  final List<String> requestedSearchKeywords = <String>[];
  var recommendedFeedRequests = 0;
  Completer<List<BiliSearchResult>>? searchCompleter;
  bool loggedIn = false;
  int generatedQrTickets = 0;

  int get followingRequests =>
      libraryHttpClient.requestCount('/x/relation/followings');

  int get spaceProfileRequests =>
      libraryHttpClient.requestCount('/x/web-interface/card');

  int get spaceVideoRequests =>
      libraryHttpClient.requestCount('/x/space/wbi/arc/search');

  @override
  Future<List<BiliFeedVideo>> fetchRecommendedFeed({int page = 1}) async {
    recommendedFeedRequests += 1;
    return page == 1 ? feedItems : const <BiliFeedVideo>[];
  }

  @override
  Future<BiliUserProfile> fetchCurrentUserProfile() async {
    return BiliUserProfile(
      isLoggedIn: loggedIn,
      name: loggedIn ? '测试用户' : '未登录',
      avatarUrl: '',
      mid: loggedIn ? 42 : null,
    );
  }

  @override
  Future<BiliQrLoginTicket> generateQrLoginTicket() async {
    generatedQrTickets += 1;
    return BiliQrLoginTicket(
      url: 'https://example.test/tv-qr/$generatedQrTickets',
      qrcodeKey: 'tv-key-$generatedQrTickets',
    );
  }

  @override
  Future<BiliQrLoginPollResult> pollQrLogin(String qrcodeKey) async {
    return const BiliQrLoginPollResult(
      status: BiliQrLoginStatus.waitingForScan,
      message: '等待扫码',
    );
  }

  @override
  Future<List<BiliSearchResult>> searchVideos(
    String keyword, {
    int page = 1,
  }) async {
    requestedSearchKeywords.add(keyword);
    final completer = searchCompleter;
    if (page == 1 && completer != null) {
      searchCompleter = null;
      return completer.future;
    }
    return page == 1 ? searchResults : const <BiliSearchResult>[];
  }

  @override
  Future<BiliVideoDetail> fetchVideoDetail(String bvid) async {
    requestedVideoDetails.add(bvid);
    return _playbackDetail();
  }

  @override
  Future<List<BiliRegionVideo>> fetchRegionVideos(
    BiliRegionSection section, {
    int page = 1,
  }) async {
    requestedSections.add(section);
    if (page != 1) {
      return const <BiliRegionVideo>[];
    }
    return List<BiliRegionVideo>.generate(
      12,
      (index) => BiliRegionVideo(
        id: '${section.id}-$index',
        title: '${section.name}内容 $index',
        coverUrl: '',
        url: 'https://example.test/${section.id}/$index',
        bvid: section.apiType == BiliRegionApiType.ranking
            ? 'BVREGION${index.toString().padLeft(4, '0')}'
            : null,
        seasonId: section.apiType == BiliRegionApiType.pgc
            ? 7000 + index
            : null,
        subtitle: section.name,
        indexLabel: '更新至 ${index + 1}',
        scoreLabel: '9.$index',
        followCountLabel: '${index + 2}万追番',
      ),
    );
  }

  @override
  Future<BiliVideoDetail> fetchPgcSeasonFirstEpisodeDetail(int seasonId) async {
    return _pgcPlaybackDetail();
  }
}

final class _FakeTvHomeLibraryHttpClient implements HttpClient {
  _FakeTvHomeLibraryHttpClient({this.emptyFollowing = false});

  final bool emptyFollowing;
  final List<Uri> requestedUris = <Uri>[];
  String? _userAgent;

  int requestCount(String path) =>
      requestedUris.where((uri) => uri.path == path).length;

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) => _userAgent = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUris.add(url);
    return _FakeTvHomeHttpRequest(_responseFor(url));
  }

  _FakeTvHomeHttpResponse _responseFor(Uri url) {
    if (url.path == '/x/web-interface/nav') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'isLogin': true,
          'mid': 42,
          'wbi_img': <String, Object?>{
            'img_url': 'https://i0.hdslb.com/bfs/wbi/img.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/sub.png',
          },
        },
      });
    }
    if (url.path == '/x/relation/followings') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': emptyFollowing
              ? const <Object?>[]
              : <Object?>[
                  <String, Object?>{
                    'mid': 7,
                    'uname': '测试 UP',
                    'face': '',
                    'sign': '简介',
                  },
                ],
        },
      });
    }
    if (url.path == '/x/web-interface/card') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'card': <String, Object?>{
            'mid': 7,
            'name': '测试 UP 空间',
            'face': '',
            'sign': '空间简介',
            'fans': 12000,
          },
          'follower': 12000,
          'archive_count': 1,
        },
      });
    }
    if (url.path == '/x/space/wbi/arc/search') {
      return _json(<String, Object?>{
        'code': 0,
        'data': <String, Object?>{
          'list': <String, Object?>{
            'vlist': <Object?>[
              <String, Object?>{
                'aid': 70,
                'bvid': 'BV1space0001',
                'title': '空间视频',
                'pic': '',
                'length': '02:03',
                'created': 1786291200,
                'play': 12000,
                'mid': 7,
                'author': '测试 UP 空间',
              },
            ],
          },
          'page': <String, Object?>{'pn': 1, 'ps': 30, 'count': 1},
        },
      });
    }
    return _json(<String, Object?>{'code': 0, 'data': <String, Object?>{}});
  }

  _FakeTvHomeHttpResponse _json(Map<String, Object?> value) {
    return _FakeTvHomeHttpResponse(jsonEncode(value));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpRequest implements HttpClientRequest {
  _FakeTvHomeHttpRequest(this.response);

  final _FakeTvHomeHttpResponse response;
  final HttpHeaders _headers = _FakeTvHomeHttpHeaders();
  int _contentLength = -1;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) => _contentLength = value;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  const _FakeTvHomeHttpResponse(this.body);

  final String body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  HttpHeaders get headers => _FakeTvHomeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeTvHomeHttpHeaders implements HttpHeaders {
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) => _contentType = value;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
