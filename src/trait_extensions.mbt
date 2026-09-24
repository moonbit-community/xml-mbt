///|
pub extend SourcePosition with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourcePosition with Eq::{not_equal, equal}

///|
pub extend SourceSpan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SourceSpan with Eq::{not_equal, equal}

///|
pub extend XmlAttribute with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend XmlAttribute with Eq::{not_equal, equal}

///|
pub extend Event with Eq::{not_equal, equal}

///|
pub extend XmlError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend XmlError with Eq::{not_equal, equal}

///|
pub extend XmlName with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend XmlName with Eq::{not_equal, equal}

///|
pub extend NamespaceDeclaration with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NamespaceDeclaration with Eq::{not_equal, equal}

///|
pub extend NamespaceAttribute with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NamespaceAttribute with Eq::{not_equal, equal}

///|
pub extend NamespaceElement with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NamespaceElement with Eq::{not_equal, equal}

///|
pub extend NamespaceEventKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NamespaceEventKind with Eq::{not_equal, equal}

///|
pub extend NamespaceEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend NamespaceEvent with Eq::{not_equal, equal}

///|
pub extend WriterError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WriterError with Eq::{not_equal, equal}

///|
pub extend XmlElement with Eq::{not_equal, equal}

///|
pub extend EventKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EventKind with Eq::{not_equal, equal}

///|
pub extend XmlErrorKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend XmlErrorKind with Eq::{not_equal, equal}

///|
pub extend XmlElement with Show::{to_string, output}

///|
pub extend XmlElement with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Event with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Event with Show::{to_string, output}

///|
pub extend EventKind with Show::{to_string, output}

///|
pub extend XmlErrorKind with Show::{to_string, output}

///|
pub extend XmlError with Show::{to_string, output}
