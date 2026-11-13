import Foundation

/// AAPI category labels — mirrors the original spreadsheet's hidden `Lists` tab.
/// If APPIC revises the AAPI, this is the one file to update.
public enum Vocab {
    public static let degrees = ["Doctoral", "Terminal Masters"]

    public static let settingTypes = [
        "Child Guidance Clinic",
        "Community Mental Health Center",
        "Department Clinic",
        "Forensic/Justice Setting (e.g., jail, prison)",
        "Inpatient Psychiatric Hospital",
        "Medical Clinic/Hospital",
        "Outpatient Psychiatric Clinic/Hospital",
        "Partial Hospitalization/Intensive Outpatient Programs",
        "Private Practice",
        "Residential/Group Home",
        "School",
        "University Counseling Center/Student Mental Health Center",
        "VA Medical Center",
        "Other",
    ]

    public static let races = [
        "African American/Black/African Origin",
        "Asian American/Asian Origin/Pacific Islander",
        "Latino-a/Hispanic",
        "American Indian/Alaska Native/Aboriginal Canadian",
        "European Origin/White",
        "Biracial/Multiracial",
        "Other",
    ]
    public static let genders = ["Male", "Female", "Transgender", "Other"]
    public static let orientations = ["Heterosexual", "Gay", "Lesbian", "Bisexual", "Other"]

    public static let clientAges = [
        "0-2 years old", "3-5 years old", "6-12 years old", "13-17 years old",
        "18-64 years old", "65+ years old", "Unknown age",
    ]
    public static let adultAges: Set<String> = ["18-64 years old", "65+ years old"]
    public static let childAges: Set<String> = ["0-2 years old", "3-5 years old", "6-12 years old",
                                                "13-17 years old"]

    public static let disabilities = [
        "Physical/Orthopedic Disability",
        "Blind/Visually Impaired",
        "Deaf/Hard of Hearing",
        "Learning/Cognitive Disability",
        "Developmental Disability",
        "Serious Mental Illness",
        "Other",
    ]

    public static let groupTypes = ["Group Therapy", "Family Therapy", "Couples Therapy"]
    public static let groupAges = ["18+ years old", "13-17 years old", "0-12 years old", "Unknown age"]

    // MARK: Intervention

    public static let individualTherapy = "Individual Therapy"
    public static let careerCounseling = "Career Counseling"
    public static let groupCounseling = "Group Counseling"
    public static let familyTherapy = "Family Therapy"
    public static let couplesTherapy = "Couples Therapy"

    public static let interventionSections: [(String, [String])] = [
        ("Individual Therapy", [individualTherapy]),
        ("Career Counseling", [careerCounseling]),
        ("Group Counseling", [groupCounseling]),
        ("Family / Couples Therapy", [familyTherapy, couplesTherapy]),
        ("School Counseling", [
            "School Counseling - Consultation",
            "School Counseling - Direct Intervention",
            "School Counseling - Other (specify)",
        ]),
        ("Other Psychological Interventions", [
            "Telephone-Based Intervention Experience",
            "Sport Psychology/Performance Enhancement",
            "Medical/Health-Related Interventions",
            "Intake Interview/Structured Interview",
            "Substance Abuse Interventions",
            "Consultation (with the client or a parent, teacher, etc. of the client)",
            "Other Interventions (specify)",
        ]),
        ("Other Psychological Experience with Students and/or Organizations", [
            "Supervision of Other Students Performing Intervention and Assessment Activities",
            "Program Development/Outreach Programming",
            "Outcome Assessment of Programs or Projects",
            "Systems Intervention/Organizational Consultation/Performance Improvement",
            "Other Psychological Experience with Students and/or Organizations (specify)",
        ]),
    ]
    public static let serviceTypes: [String] = interventionSections.flatMap { $0.1 }

    /// Service types delivered to a client group of a given type.
    public static let groupServiceToGroupType: [String: String] = [
        groupCounseling: "Group Therapy",
        familyTherapy: "Family Therapy",
        couplesTherapy: "Couples Therapy",
    ]
    /// Service types that don't need a client attached (organisational work).
    public static let noClientOK: Set<String> = Set(interventionSections.last!.1).union([
        "School Counseling - Consultation",
        "Consultation (with the client or a parent, teacher, etc. of the client)",
    ])

    public static let careerBuckets: [(String, Set<String>)] = [
        ("Adults (18+)", adultAges),
        ("Adolescents (13-17)", ["13-17 years old"]),
        ("Other / unknown age", ["0-2 years old", "3-5 years old", "6-12 years old", "Unknown age"]),
    ]

    // MARK: Assessment

    public static let assessmentTypes = ["Psychodiagnostic", "Neuropsychological", "Telephone-Based", "Other"]
    public static let assessmentPurposes = ["Clinical", "Research"]
    public static let reportTypes = ["Standard Report", "Integrated Report"]
    public static let integratedReport = "Integrated Report"

    // MARK: Supervision

    public static let supervisionTypes = ["Individual Supervision", "Group Supervision"]
    public static let supervisorTypes = [
        "Licensed Psychologist",
        "Allied Mental Health Professional (e.g., social workers, marriage and family therapists, psychiatrists)",
        "Other (e.g., advanced grad student supervised by licensed psychologist)",
    ]
    public static let supervisorTypeShort: [String: String] = [
        supervisorTypes[0]: "Licensed Psychologist",
        supervisorTypes[1]: "Allied Mental Health Professional",
        supervisorTypes[2]: "Other",
    ]

    // MARK: Support

    public static let supportActivities = [
        "Administration",
        "Assessment Report Writing",
        "Case Conferences",
        "Case Management",
        "Case Consultation",
        "Chart Review",
        "Clinical Writing/Progress Notes",
        "Coordinating Community Resources",
        "Grand Rounds",
        "Intervention Planning",
        "Observation",
        "Phone Support (including phone sessions prior to 3/2/20)",
        "Professional Consultation",
        "Professional Development",
        "Psychoeducational Group/Workshop",
        "Psychological Assessment Scoring/Interpretation",
        "Reading/Research/Preparation",
        "Seminars/Didactic Training",
        "Staff Meeting",
        "Video/Audio/Digital Recording Review",
        "Other",
    ]

    // MARK: Cross-cutting

    public static let modalities = ["In person", "Telehealth (video)", "Telephone"]
    public static let defaultModality = "In person"
    public static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                                  "Saturday", "Sunday"]

    public static func activities(for category: HourCategory) -> [String] {
        switch category {
        case .intervention: return serviceTypes
        case .assessment: return assessmentTypes
        case .supervision: return supervisionTypes
        case .support: return supportActivities
        }
    }

    public static func needsSpecify(_ activity: String) -> Bool { activity.contains("(specify)") }

    public static func groupType(for activity: String) -> String? { groupServiceToGroupType[activity] }

    /// "Adults" / "Children/Adolescents" / nil — for report & instrument tables.
    public static func ageBand(_ ageGroup: String?) -> String? {
        guard let a = ageGroup else { return nil }
        if adultAges.contains(a) { return "Adults" }
        if childAges.contains(a) { return "Children/Adolescents" }
        return nil
    }
}

public enum HourCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case intervention, assessment, supervision, support
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .intervention: return "Intervention"
        case .assessment: return "Assessment"
        case .supervision: return "Supervision"
        case .support: return "Support"
        }
    }
}
