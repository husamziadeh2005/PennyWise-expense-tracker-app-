import 'package:expense_tracker/features/auth/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toE164', () {
    test('Jordanian local mobile numbers', () {
      expect(AuthValidators.toE164('0791234567', country: 'Jordan'), '+962791234567');
      expect(AuthValidators.toE164('079 123 4567', country: 'Jordan'), '+962791234567');
      expect(AuthValidators.toE164('791234567', country: 'Jordan'), '+962791234567');
      expect(AuthValidators.toE164('0771234567', country: 'Jordan'), '+962771234567');
      expect(AuthValidators.toE164('0781234567', country: 'Jordan'), '+962781234567');
    });

    test('international formats', () {
      expect(AuthValidators.toE164('+962791234567'), '+962791234567');
      expect(AuthValidators.toE164('00962791234567'), '+962791234567');
      expect(AuthValidators.toE164('962791234567', country: 'Jordan'), '+962791234567');
      expect(AuthValidators.toE164('0501234567', country: 'Saudi Arabia'), '+966501234567');
      expect(AuthValidators.toE164('(415) 555-2671', country: 'United States'), '+14155552671');
    });

    test('rejects invalid numbers', () {
      expect(AuthValidators.toE164('', country: 'Jordan'), isNull);
      expect(AuthValidators.toE164('12345', country: 'Jordan'), isNull);
      expect(AuthValidators.toE164('0691234567', country: 'Jordan'), isNull); // not a JO mobile
      expect(AuthValidators.toE164('079123', country: 'Jordan'), isNull);
      expect(AuthValidators.toE164('0791234567', country: 'Other'), isNull); // needs +code
      expect(AuthValidators.toE164('abc'), isNull);
    });
  });

  group('password', () {
    test('accepts strong passwords', () {
      expect(AuthValidators.password('Penny2026'), isNull);
    });
    test('rejects weak passwords', () {
      expect(AuthValidators.password(''), isNotNull);
      expect(AuthValidators.password('Ab1'), isNotNull);
      expect(AuthValidators.password('alllowercase1'), isNotNull);
      expect(AuthValidators.password('ALLUPPERCASE1'), isNotNull);
      expect(AuthValidators.password('NoDigitsHere'), isNotNull);
    });
  });

  group('email / name / otp', () {
    test('email', () {
      expect(AuthValidators.email('user@example.com'), isNull);
      expect(AuthValidators.email(' user@example.com '), isNull);
      expect(AuthValidators.email('user@'), isNotNull);
      expect(AuthValidators.email('user.example.com'), isNotNull);
      expect(AuthValidators.email(''), isNotNull);
    });
    test('name', () {
      expect(AuthValidators.fullName('Hussam'), isNull);
      expect(AuthValidators.fullName('  '), isNotNull);
    });
    test('otp', () {
      expect(AuthValidators.otp('123456'), isNull);
      expect(AuthValidators.otp('12345'), isNotNull);
      expect(AuthValidators.otp('12a456'), isNotNull);
    });
  });
}
