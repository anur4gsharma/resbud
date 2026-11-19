import '../generation/generation_models.dart';

class AuthorAffiliationIssue {
  const AuthorAffiliationIssue({
    required this.message,
    required this.isError,
    this.authorId,
    this.affiliationId,
  });

  final String message;
  final bool isError;
  final String? authorId;
  final String? affiliationId;
}

class AuthorAffiliationValidationReport {
  const AuthorAffiliationValidationReport({
    this.issues = const [],
  });

  final List<AuthorAffiliationIssue> issues;

  bool get isValid => !issues.any((i) => i.isError);
  List<AuthorAffiliationIssue> get errors => issues.where((i) => i.isError).toList();
  List<AuthorAffiliationIssue> get warnings => issues.where((i) => !i.isError).toList();

  List<String> get errorMessages => errors.map((e) => e.message).toList();
  List<String> get warningMessages => warnings.map((w) => w.message).toList();
}

class AuthorAffiliationValidator {
  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  static final RegExp _orcidRegex = RegExp(
    r'^\d{4}-\d{4}-\d{4}-[\dX]{4}$',
  );

  static AuthorAffiliationValidationReport validate({
    required List<AuthorMetadataPayload> authors,
    required List<AuthorAffiliationPayload> affiliations,
  }) {
    final issues = <AuthorAffiliationIssue>[];
    final affiliationMap = <String, AuthorAffiliationPayload>{};
    final seenAffiliationKeys = <String, String>{};

    // 1. Validate affiliations
    for (var i = 0; i < affiliations.length; i++) {
      final aff = affiliations[i];
      final affId = aff.id.trim();

      if (affId.isEmpty) {
        issues.add(
          AuthorAffiliationIssue(
            message: 'Affiliation #${i + 1} has an empty identifier.',
            isError: true,
            affiliationId: aff.id,
          ),
        );
      } else if (affiliationMap.containsKey(affId)) {
        issues.add(
          AuthorAffiliationIssue(
            message: 'Duplicate affiliation ID "$affId".',
            isError: true,
            affiliationId: affId,
          ),
        );
      } else {
        affiliationMap[affId] = aff;
      }

      if (aff.institution.trim().isEmpty) {
        issues.add(
          AuthorAffiliationIssue(
            message: 'Affiliation "${affId.isNotEmpty ? affId : '#${i + 1}'}" is missing required institution name.',
            isError: true,
            affiliationId: affId,
          ),
        );
      }

      // Check duplicate affiliation content
      final contentKey = '${aff.department?.trim().toLowerCase() ?? ''}|'
          '${aff.institution.trim().toLowerCase()}|'
          '${aff.city?.trim().toLowerCase() ?? ''}|'
          '${aff.country?.trim().toLowerCase() ?? ''}';
      if (seenAffiliationKeys.containsKey(contentKey)) {
        issues.add(
          AuthorAffiliationIssue(
            message: 'Affiliation "${aff.id}" duplicates the institution and department of "${seenAffiliationKeys[contentKey]}". Consider reusing the existing affiliation.',
            isError: false,
            affiliationId: aff.id,
          ),
        );
      } else {
        seenAffiliationKeys[contentKey] = aff.id;
      }
    }

    // 2. Validate authors
    final seenAuthorIds = <String>{};
    var expectedOrder = 1;

    for (var idx = 0; idx < authors.length; idx++) {
      final author = authors[idx];
      final authorId = author.effectiveId;
      final authorLabel = author.name.trim().isNotEmpty ? author.name.trim() : 'Author #${idx + 1}';

      // Empty name
      if (author.name.trim().isEmpty) {
        issues.add(
          AuthorAffiliationIssue(
            message: 'Author #${idx + 1} has an empty name.',
            isError: true,
            authorId: author.id,
          ),
        );
      }

      // Duplicate author ID
      if (author.id != null && author.id!.trim().isNotEmpty) {
        if (seenAuthorIds.contains(author.id!.trim())) {
          issues.add(
            AuthorAffiliationIssue(
              message: 'Duplicate author ID "${author.id}".',
              isError: true,
              authorId: author.id,
            ),
          );
        } else {
          seenAuthorIds.add(author.id!.trim());
        }
      }

      // Check author ordering sequence
      if (author.order != expectedOrder) {
        issues.add(
          AuthorAffiliationIssue(
            message: '$authorLabel has order ${author.order}, but expected sequence position is $expectedOrder.',
            isError: false,
            authorId: authorId,
          ),
        );
      }
      expectedOrder++;

      // Check affiliation references
      if (author.affiliationIds.isEmpty && affiliations.isNotEmpty) {
        issues.add(
          AuthorAffiliationIssue(
            message: '$authorLabel has no assigned affiliations.',
            isError: false,
            authorId: authorId,
          ),
        );
      }

      for (final refId in author.affiliationIds) {
        if (!affiliationMap.containsKey(refId)) {
          issues.add(
            AuthorAffiliationIssue(
              message: '$authorLabel references non-existent affiliation "$refId".',
              isError: true,
              authorId: authorId,
              affiliationId: refId,
            ),
          );
        }
      }

      // Email validation
      if (author.email != null && author.email!.trim().isNotEmpty) {
        final email = author.email!.trim();
        if (!_emailRegex.hasMatch(email)) {
          issues.add(
            AuthorAffiliationIssue(
              message: '$authorLabel has invalid email format "$email".',
              isError: false,
              authorId: authorId,
            ),
          );
        }
      }

      // ORCID validation
      if (author.orcid != null && author.orcid!.trim().isNotEmpty) {
        final orcid = author.orcid!.trim();
        if (!_orcidRegex.hasMatch(orcid)) {
          issues.add(
            AuthorAffiliationIssue(
              message: '$authorLabel has invalid ORCID format "$orcid" (expected format: 0000-0000-0000-0000).',
              isError: false,
              authorId: authorId,
            ),
          );
        }
      }
    }

    return AuthorAffiliationValidationReport(issues: List.unmodifiable(issues));
  }
}
