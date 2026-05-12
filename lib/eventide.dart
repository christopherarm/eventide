library;

export 'src/eventide.dart' show Eventide;
export 'src/eventide_platform_interface.dart'
    show ETCalendar, ETEvent, ETAccount, ETAttendee, ETAttendeeType, ETAttendanceStatus, ETUpdateSpan;
export 'src/eventide_exception.dart'
    show
        ETException,
        ETPermissionException,
        ETNotEditableException,
        ETNotFoundException,
        ETGenericException,
        ETNotSupportedByPlatform,
        ETUserCanceledException,
        ETPresentationException;
