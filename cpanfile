on 'test' => sub {
   requires 'Test2::V0'; # Not in core for Perl v5.34.0
   requires 'Test2::Plugin::NoWarnings';
   requires 'Capture::Tiny';
};
