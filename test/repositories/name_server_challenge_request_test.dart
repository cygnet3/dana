import 'package:danawallet/data/models/name_server_challenge_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the outbound challenge request model after the
/// dead `fromJson` factory was deleted (finding t_03cb4b3b, YAGNI):
/// the repository only ever *sends* this body (POST /challenge), the server
/// never echoes the shape back, so the constructor + toJson pair must keep
/// producing exactly the snake_case wire fields the nameserver parses.
void main() {
  group('NameServerChallengeRequest (outbound-only)', () {
    const request = NameServerChallengeRequest(
      id: 'req-1',
      userName: 'alice',
      domain: 'danawallet.app',
      spAddress: 'sp1qqernutv8ar5g7m2x',
    );

    test('toJson emits exactly the fields the repository sends', () {
      expect(request.toJson(), {
        'id': 'req-1',
        'user_name': 'alice',
        'domain': 'danawallet.app',
        'sp_address': 'sp1qqernutv8ar5g7m2x',
      });
    });

    test('toJson round-trips the four wire keys by name', () {
      final json = request.toJson();
      expect(json.keys.toSet(), {'id', 'user_name', 'domain', 'sp_address'});
      // Values survive the single serialisation hop the repository performs.
      expect(json['id'], request.id);
      expect(json['user_name'], request.userName);
      expect(json['domain'], request.domain);
      expect(json['sp_address'], request.spAddress);
    });
  });
}
