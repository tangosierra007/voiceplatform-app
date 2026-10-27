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
  BundledLicence('liblinphone', ['liblinphone/LICENSE.txt']),
  BundledLicence('mediastreamer2', ['mediastreamer2/LICENSE.txt']),
  BundledLicence('oRTP', ['ortp/LICENSE.txt']),
  BundledLicence('bctoolbox', ['bctoolbox/LICENSE.txt']),
  BundledLicence('belle-sip', ['belle-sip/LICENSE.txt']),
  BundledLicence('belr', ['belr/LICENSE.txt']),
  BundledLicence('bzrtp', ['bzrtp/LICENSE.txt']),
  BundledLicence('lime', ['lime/LICENSE.txt']),
  BundledLicence('postquantumcryptoengine', ['postquantumcryptoengine/LICENSE.txt']),
  BundledLicence('msaaudio', ['msaaudio/LICENSE.txt']),
  BundledLicence('msandroidcamera2', ['msandroidcamera2/LICENSE.txt']),
  BundledLicence('mswebrtc', ['mswebrtc/COPYING']),
  BundledLicence('Ooura FFT (in mswebrtc)', ['mswebrtc-ooura/LICENSE']),
  BundledLicence('Abseil (in mswebrtc)', ['mswebrtc-abseil/LICENSE']),
  // Third-party code in the native libraries.
  BundledLicence('opus', ['opus/COPYING']),
  BundledLicence('speex', ['speex/COPYING']),
  BundledLicence('libvpx', ['libvpx/LICENSE', 'libvpx/PATENTS']),
  BundledLicence('libsrtp', ['libsrtp/LICENSE']),
  BundledLicence('mbedTLS', ['mbedtls/LICENSE']),
  BundledLicence('zlib', ['zlib/README']),
  BundledLicence('SQLite', ['sqlite/LICENSE.md']),
  BundledLicence('libjpeg-turbo', ['libjpeg-turbo/LICENSE.md', 'libjpeg-turbo/README.ijg']),
  BundledLicence('dav1d', ['dav1d/COPYING']),
  BundledLicence('jsoncpp', ['jsoncpp/LICENSE']),
  BundledLicence('ZXing-C++', ['zxing-cpp/LICENSE']),
  BundledLicence('xerces-c', ['xerces-c/LICENSE', 'xerces-c/NOTICE']),
  BundledLicence('soci', ['soci/LICENSE_1_0.txt']),
  BundledLicence('libxml2', ['libxml2/Copyright']),
  BundledLicence('OpenLDAP', ['openldap/LICENSE', 'openldap/COPYRIGHT']),
  BundledLicence('liboqs (ML-KEM)', ['liboqs/LICENSE.txt']),
  BundledLicence('LLVM libc++', ['libc++/LICENSE.TXT']),
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
