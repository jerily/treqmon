package require tcltest 2
::tcltest::configure {*}$argv -testdir [file dirname [info script]]
exit [::tcltest::runAllTests]
