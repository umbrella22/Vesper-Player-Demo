import '../models/bili_models.dart';
import 'bili_api_core.dart';

const biliDashRequestVariants = <BiliDashRequestVariant>[
  BiliDashRequestVariant(
    label: 'web fnval=4048',
    fnval: biliDashFnval,
    extraParams: <String, Object?>{
      'gaia_source': 'pre-load',
      'isGaiaAvoided': 'true',
      'from_client': 'BROWSER',
      'web_location': 1315873,
    },
  ),
  BiliDashRequestVariant(
    label: 'web fnval=976',
    fnval: biliDashCompatFnval,
    extraParams: <String, Object?>{
      'gaia_source': 'pre-load',
      'isGaiaAvoided': 'true',
      'from_client': 'BROWSER',
      'web_location': 1315873,
    },
  ),
  BiliDashRequestVariant(
    label: 'plain fnval=976',
    fnval: biliDashCompatFnval,
    extraParams: <String, Object?>{'high_quality': 1},
  ),
];

Map<String, Object?> buildBiliDashPlayUrlParams({
  required BiliVideoDetail detail,
  required BiliVideoPageEntry page,
  required BiliDashRequestVariant variant,
  required String session,
}) {
  return <String, Object?>{
    'avid': page.aid ?? detail.aid,
    'bvid': page.bvid ?? detail.bvid,
    'cid': page.cid,
    'qn': biliMaxVideoQuality,
    'otype': 'json',
    'fnver': 0,
    'fnval': variant.fnval,
    'fourk': 1,
    'support_multi_audio': 'true',
    'session': session,
    ...variant.extraParams,
  };
}
