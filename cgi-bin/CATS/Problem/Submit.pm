package CATS::Problem::Submit;

use strict;
use warnings;

use CATS::Constants;
use CATS::DB;
use CATS::DevEnv;
use CATS::Misc qw(
    $t $is_jury $is_team $cid $uid $contest $is_virtual $virtual_diff_time
    msg url_f);
use CATS::Request;
use CATS::Web qw(param upload_source);

sub can_upsolve {
    my ($tag) = $dbh->selectrow_array(q~
         SELECT CA.tag FROM contest_accounts CA
             WHERE CA.contest_id = ? AND CA.account_id = ?~, undef,
         $cid, $uid || 0);
    !!(($tag || '') =~ /upsolve/);
}

sub problem_submit_too_frequent {
    my ($submit_uid) = @_;
    # Protect from Denial of Service -- disable too frequent submissions.
    my $prev = $dbh->selectcol_arrayref(q~
        SELECT FIRST 2 CAST(CURRENT_TIMESTAMP - R.submit_time AS DOUBLE PRECISION) FROM reqs R
        WHERE R.account_id = ?
        ORDER BY R.submit_time DESC~, {},
        $submit_uid);
    my $SECONDS_PER_DAY = 24 * 60 * 60;
    ($prev->[0] || 1) < 3/$SECONDS_PER_DAY || ($prev->[1] || 1) < 60/$SECONDS_PER_DAY;
}

sub determine_state {
    return $cats::st_ignore_submit if param('ignore');
    !$is_jury && !param('np') && $CATS::Config::TB && CATS::Web::user_agent =~ /$CATS::Config::TB/ ?
        $cats::st_ignore_submit : $cats::st_not_processed;
}

sub problems_submit {
    my $pid = param('problem_id')
        or return msg(1012);
    $is_team or return msg(1116);

    # Use explicit empty string comparisons to avoid problems with solutions containing only '0'.
    my $file = param('source') // '';
    my $source_text = param('source_text') // '';
    $file ne '' || $source_text ne '' or return msg(1009);
    $file eq '' || $source_text eq '' or return msg(1042);
    length($file) <= 200 or return msg(1010);
    if ($source_text eq '') {
        $source_text = upload_source('source');
        $source_text ne '' or return msg(1011);
    }

    my $did = param('de_id') or return msg(1013);

    my ($time_since_start, $time_since_finish, $is_official, $status, $title) = $dbh->selectrow_array(qq~
        SELECT
            CAST(CURRENT_TIMESTAMP - $virtual_diff_time - C.start_date AS DOUBLE PRECISION),
            CAST(CURRENT_TIMESTAMP- $virtual_diff_time - C.finish_date AS DOUBLE PRECISION),
            C.is_official, CP.status, P.title
        FROM contests C
        INNER JOIN contest_problems CP ON CP.contest_id = C.id
        INNER JOIN problems P ON P.id = CP.problem_id
        WHERE C.id = ? AND CP.problem_id = ?~, undef,
        $cid, $pid) or return msg(1012);

    unless ($is_jury) {
        $time_since_start >= 0
            or return msg(1080);
        $time_since_finish <= 0 || $is_virtual || can_upsolve
            or return msg(1081);
        !defined $status || $status < $cats::problem_st_disabled
            or return msg(1124, $title);

        # During the official contest, do not accept submissions for other contests.
        if (!$is_official || $is_virtual) {
            my ($current_official) = $contest->current_official;
            !$current_official
                or return msg(1123, $current_official->{title});
        }
    }

    my $submit_uid = $uid // ($contest->is_practice ? get_anonymous_uid() : die);

    return msg(1131) if problem_submit_too_frequent($submit_uid);

    my $prev_reqs_count;
    if ($contest->{max_reqs} && !$is_jury) {
        $prev_reqs_count = $dbh->selectrow_array(q~
            SELECT COUNT(*) FROM reqs R
            WHERE R.account_id = ? AND R.problem_id = ? AND R.contest_id = ?~, {},
            $submit_uid, $pid, $cid);
        return msg(1137) if $prev_reqs_count >= $contest->{max_reqs};
    }

    if ($did eq 'by_extension') {
        my $de = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1 }))->by_file_extension($file)
            or return msg(1013);
        $did = $de->{id};
        $t->param(de_name => $de->{description});
    }

    # Forbid repeated submissions of the identical code with the same DE.
    my $source_hash = CATS::Utils::source_hash($source_text);
    my ($same_source, $prev_submit_time) = $dbh->selectrow_array(q~
        SELECT FIRST 1 S.req_id, R.submit_time
        FROM sources S INNER JOIN reqs R ON S.req_id = R.id
        WHERE
            R.account_id = ? AND R.problem_id = ? AND
            R.contest_id = ? AND S.hash = ? AND S.de_id = ?~, undef,
        $submit_uid, $pid, $cid, $source_hash, $did);
    $same_source and return msg(1132, $prev_submit_time);

    my $rid = CATS::Request::insert($pid, $cid, $submit_uid, [ CATS::DevEnv->new(CATS::JudgeDB::get_DEs())->bitmap_by_ids($did) ], { state => determine_state });

    my $s = $dbh->prepare(q~
        INSERT INTO sources(req_id, de_id, src, fname, hash) VALUES (?, ?, ?, ?, ?)~);
    $s->bind_param(1, $rid);
    $s->bind_param(2, $did);
    $s->bind_param(3, $source_text, { ora_type => 113 } ); # blob
    $s->bind_param(4, $file ? "$file" :
        "$rid." . CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ id => $did }))->default_extension($did));
    $s->bind_param(5, $source_hash);
    $s->execute;
    $dbh->commit;

    $t->param(solution_submitted => 1, href_console => url_f('console'));
    $time_since_finish > 0 ? msg(1087) :
    defined $prev_reqs_count ?
        msg(1088, $contest->{max_reqs} - $prev_reqs_count - 1) : msg(1014);
}

sub problems_submit_std_solution {
    my $pid = param('problem_id');

    defined $pid or return msg(1012);

    my ($title) = $dbh->selectrow_array(q~
        SELECT title FROM problems WHERE id = ?~, undef,
        $pid) or return msg(1012);

    my $sol_count = 0;

    my $c = $dbh->prepare(q~
        SELECT src, de_id, fname
        FROM problem_sources
        WHERE problem_id = ? AND (stype = ? OR stype = ?)~);
    $c->execute($pid, $cats::solution, $cats::adv_solution);

    my $de_list = CATS::DevEnv->new(CATS::JudgeDB::get_DEs({ active_only => 1 }));

    while (my ($src, $did, $fname) = $c->fetchrow_array) {
        my $rid = CATS::Request::insert($pid, $cid, $uid, [ $de_list->bitmap_by_ids($did) ]);

        my $s = $dbh->prepare(q~
            INSERT INTO sources(req_id, de_id, src, fname) VALUES (?, ?, ?, ?)~);
        $s->bind_param(1, $rid);
        $s->bind_param(2, $did);
        $s->bind_param(3, $src, { ora_type => 113 } ); # blob
        $s->bind_param(4, $fname);
        $s->execute;

        ++$sol_count;
    }

    $sol_count or return msg(1106, $title);
    $dbh->commit;
    $t->param(solution_submitted => 1, href_console => url_f('console'));
    msg(1107, $title, $sol_count);
}

1;
