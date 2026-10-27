import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A component compiled into the liblinphone SDK's native libraries and the
/// licence texts that ship for it in `packages/vp_linphone/licenses/`.
/// NOTICE (repository root) lists the same components with their source.
final class BundledLicence {
  const BundledLicence(this.name, this.files, {this.note});
  final String name;

  /// Paths under `licenses/`; empty when no text could be obtained.
  final List<String> files;
  final String? note;
}

const String _notObtained =
    'The upstream licence text for this component could not be obtained or '
    'confirmed for the version in the liblinphone SDK. See NOTICE in the '
    'source repository.';

/// Kept in step with NOTICE and the licenses/ folder (test/licenses_test.dart).
const List<BundledLicence> bundledLicences = [
  // Belledonne Communications, from linphone-sdk 5.5.39 (exact).
  BundledLicence('liblinphone', ['LICENSE.liblinphone']),
  BundledLicence('mediastreamer2', ['LICENSE.mediastreamer2']),
  BundledLicence('oRTP', ['LICENSE.ortp']),
  BundledLicence('bctoolbox', ['LICENSE.bctoolbox']),
  BundledLicence('belle-sip', ['LICENSE.belle-sip']),
  BundledLicence('belr', ['LICENSE.belr']),
  BundledLicence('bzrtp', ['LICENSE.bzrtp']),
  BundledLicence('lime', ['LICENSE.lime']),
  BundledLicence('postquantumcryptoengine', ['LICENSE.postquantumcryptoengine']),
  BundledLicence('msaaudio', ['LICENSE.msaaudio']),
  BundledLicence('msandroidcamera2', ['LICENSE.msandroidcamera2']),
  BundledLicence('mswebrtc', ['LICENSE.mswebrtc']),
  BundledLicence('Ooura FFT (in mswebrtc)', ['LICENSE.mswebrtc-ooura']),
  BundledLicence('Abseil (in mswebrtc)', ['LICENSE.mswebrtc-abseil']),
  // Third-party code in the native libraries.
  BundledLicence('opus', ['LICENSE.opus']),
  BundledLicence('speex', ['LICENSE.speex']),
  BundledLicence('libvpx', ['LICENSE.libvpx', 'LICENSE.libvpx-patents']),
  BundledLicence('libsrtp', ['LICENSE.libsrtp']),
  BundledLicence('mbedTLS', ['LICENSE.mbedtls']),
  BundledLicence('zlib', ['LICENSE.zlib']),
  BundledLicence('SQLite', ['LICENSE.sqlite']),
  BundledLicence('libjpeg-turbo', ['LICENSE.libjpeg-turbo', 'LICENSE.libjpeg-turbo-ijg']),
  BundledLicence('dav1d', ['LICENSE.dav1d']),
  BundledLicence('jsoncpp', ['LICENSE.jsoncpp']),
  BundledLicence('ZXing-C++', ['LICENSE.zxing-cpp']),
  BundledLicence('xerces-c', ['LICENSE.xerces-c', 'LICENSE.xerces-c-notice']),
  BundledLicence('soci', ['LICENSE.soci']),
  BundledLicence('libxml2', ['LICENSE.libxml2']),
  BundledLicence('OpenLDAP', ['LICENSE.openldap', 'LICENSE.openldap-copyright']),
  BundledLicence('liboqs (ML-KEM)', ['LICENSE.liboqs']),
  BundledLicence('LLVM libc++', ['LICENSE.libc++']),
  BundledLicence('aom', [], note: _notObtained),
  BundledLicence('GSM 06.10', [], note: _notObtained),
  BundledLicence('BroadVoice16', [], note: _notObtained),
  BundledLicence('decaf (Ed448)', [], note: _notObtained),
  BundledLicence('WebRTC audio processing (in mswebrtc)', [], note: _notObtained),
];

/// Adds the native components' licences to Flutter's [LicenseRegistry], so the
/// in-app licence list ("Open source licences") shows them. Call once at app
/// start, before the licence page can open. Texts load lazily from the
/// plugin's assets.
void addVpLinphoneLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final b = bundle ?? rootBundle;
    for (final l in bundledLicences) {
      final texts = <String>[for (final f in l.files) await b.loadString('packages/vp_linphone/licenses/$f'), ?l.note];
      yield LicenseEntryWithLineBreaks(['${l.name} (in the liblinphone SDK)'], texts.join('\n\n'));
    }
  });
}
