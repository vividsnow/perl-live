requires 'perl', '5.022';
requires 'AnyEvent', '7.17';
requires 'PadWalker', '2.5';
requires 'Package::Stash', '0.40';
requires 'JSON::PP';

recommends 'EV';
recommends 'Package::Stash::XS';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::Harness';
};
