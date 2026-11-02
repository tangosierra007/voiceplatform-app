// The one 13 number tests may use (TJ's rule, 2 November 2026; README.md,
// Test data).
//
// ACMA reserves no 13 number for fiction, and every 13 number may belong to
// a business or a public service. So tests use this arbitrary shape, from
// this one place, and never a number someone uses, not even built from
// parts. It is data only: formatting, normalisation and matching. It is
// never dialled, never sent anywhere (the mock server included), and never
// in screenshots, goldens or store material. test/tool/test_numbers_test.dart
// checks it stays out of lib/, tool/mock_server/, assets/ and docs/store/,
// and that the call_engine package's copy matches.
//
// tool/check_phone_numbers.dart allows this number in this file and in
// packages/call_engine/test/support/test_numbers.dart only
// (tool/phone_numbers/allow_list.txt). Anywhere else it fails CI.
//
// 1300 and 1800 tests use ACMA's fictional numbers instead.
const arbitrary13Number = '13 00 00';
