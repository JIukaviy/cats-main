package CATS::Router;

use strict;
use warnings;

use CATS::ApiJudge;
use CATS::Contest::Results;
use CATS::Problem::Text;

use CATS::UI::About;
use CATS::UI::Compilers;
use CATS::UI::Console;
use CATS::UI::Contests;
use CATS::UI::ImportSources;
use CATS::UI::Judges;
use CATS::UI::Keywords;
use CATS::UI::LoginLogout;
use CATS::UI::Messages;
use CATS::UI::Prizes;
use CATS::UI::ProblemDetails;
use CATS::UI::Problems;
use CATS::UI::Stats;
use CATS::UI::RankTable;
use CATS::UI::RunDetails;
use CATS::UI::Users;

use CATS::Web qw(url_param param);

my $function;

my $bool = qr/1/;
my $int = qr/\d+/;
my $int_list = qr/[\d,]+/;
my $fixed = qr/[+-]?([0-9]*[.])?[0-9]+/;
my $sha = qr/[a-h0-9]+/;
my $str = qr/.+/;

sub main_routes() {
    {
        login => \&CATS::UI::LoginLogout::login_frame,
        logout => \&CATS::UI::LoginLogout::logout_frame,
        registration => \&CATS::UI::Users::registration_frame,
        profile => [ \&CATS::UI::Users::profile_frame, json => $bool, clear => $str, edit_save => $str, ],
        contests => [ \&CATS::UI::Contests::contests_frame, has_problem => $int, ],

        console_content => \&CATS::UI::Console::content_frame,
        console => \&CATS::UI::Console::console_frame,
        console_export => \&CATS::UI::Console::export,
        console_graphs => \&CATS::UI::Console::graphs,

        problems => [ \&CATS::UI::Problems::problems_frame, kw => $int, ],
        problems_udebug => [ \&CATS::UI::Problems::problems_udebug_frame, ],
        problems_retest => \&CATS::UI::Problems::problems_retest_frame,
        problem_select_testsets => [
            \&CATS::UI::ProblemDetails::problem_select_testsets_frame,
            pid => $int, save => $str, from_problems => $bool, ],
        problem_select_tags => [
            \&CATS::UI::ProblemDetails::problem_select_tags_frame,
            pid => $int, tags => $str, save => $str, from_problems => $bool, ],
        problem_limits => [
            \&CATS::UI::ProblemDetails::problem_limits_frame,
            pid => $int, cpid => $int, memory_limit => $int, time_limit => $fixed, write_limit => $int ],
        problem_download => [ \&CATS::UI::ProblemDetails::problem_download, pid => $int, ],
        problem_git_package => [ \&CATS::UI::ProblemDetails::problem_git_package, pid => $int, sha => $sha, ],
        problem_details => [ \&CATS::UI::ProblemDetails::problem_details_frame, pid => $int, ],
        problem_history => \&CATS::UI::ProblemDetails::problem_history_frame,

        users => \&CATS::UI::Users::users_frame,
        users_import => \&CATS::UI::Users::users_import_frame,
        user_stats => \&CATS::UI::Users::user_stats_frame,
        user_settings => \&CATS::UI::Users::user_settings_frame,
        user_ip => [ \&CATS::UI::Users::user_ip_frame, uid => $int, ],

        compilers => \&CATS::UI::Compilers::compilers_frame,
        judges => \&CATS::UI::Judges::judges_frame,
        keywords => \&CATS::UI::Keywords::keywords_frame,
        import_sources => \&CATS::UI::ImportSources::import_sources_frame,
        download_import_source => \&CATS::UI::ImportSources::download_frame,
        prizes => \&CATS::UI::Prizes::prizes_frame,
        contests_prizes => \&CATS::UI::Prizes::contests_prizes_frame,

        answer_box => \&CATS::UI::Messages::answer_box_frame,
        send_message_box => \&CATS::UI::Messages::send_message_box_frame,

        run_log => \&CATS::UI::RunDetails::run_log_frame,
        view_source => \&CATS::UI::RunDetails::view_source_frame,
        download_source => \&CATS::UI::RunDetails::download_source_frame,
        run_details => \&CATS::UI::RunDetails::run_details_frame,
        visualize_test => [ \&CATS::UI::RunDetails::visualize_test_frame, rid => $int, vid => $int, test_rank => $int, ],
        diff_runs => [ \&CATS::UI::RunDetails::diff_runs_frame, r1 => $int, r2 => $int, ],

        test_diff => \&CATS::UI::Stats::test_diff_frame,
        compare_tests => \&CATS::UI::Stats::compare_tests_frame,
        rank_table_content => \&CATS::UI::RankTable::rank_table_content_frame,
        rank_table => \&CATS::UI::RankTable::rank_table_frame,
        rank_problem_details => \&CATS::UI::RankTable::rank_problem_details,
        problem_text => \&CATS::Problem::Text::problem_text_frame,
        envelope => \&CATS::UI::Messages::envelope_frame,
        about => \&CATS::UI::About::about_frame,

        similarity => \&CATS::UI::Stats::similarity_frame,
        personal_official_results => \&CATS::Contest::personal_official_results,
    }
}

sub api_judge_routes() {
    {
        get_judge_id => \&CATS::ApiJudge::get_judge_id,
        api_judge_get_des => \&CATS::ApiJudge::get_DEs,
        api_judge_get_problem => [ \&CATS::ApiJudge::get_problem, pid => $int, ],
        api_judge_get_problem_sources => [ \&CATS::ApiJudge::get_problem_sources, pid => $int, ],
        api_judge_get_problem_tests => [ \&CATS::ApiJudge::get_problem_tests, pid => $int, ],
        api_judge_is_problem_uptodate => [ \&CATS::ApiJudge::is_problem_uptodate, pid => $int, date => $str, ],
        api_judge_save_log_dump => [ \&CATS::ApiJudge::save_log_dump, req_id => $int, dump => undef, ],
        api_judge_select_request => [ \&CATS::ApiJudge::select_request, supported_DEs => $int_list, ],
        api_judge_set_request_state => [
            \&CATS::ApiJudge::set_request_state,
            req_id => $int,
            state => $int,
            problem_id => $int,
            contest_id => $int,
            failed_test => $int,
        ],
        api_judge_delete_req_details => [ \&CATS::ApiJudge::delete_req_details, req_id => $int, ],
        api_judge_insert_req_details => [ \&CATS::ApiJudge::insert_req_details, params => $str, ],
        api_judge_get_testset => [ \&CATS::ApiJudge::get_testset, req_id => $int, update => $int, ],
    }
}

sub parse_uri {
    CATS::Web::get_uri =~ m~/cats/(|main.pl)$~;
}

sub route {
    $function = url_param('f') || '';
    my $route =
        main_routes->{$function} ||
        api_judge_routes->{$function} ||
        \&CATS::UI::About::about_frame;
    my $fn = $route;
    my $p = {};
    if (ref $route eq 'ARRAY') {
        $fn = shift @$route;
        while (@$route) {
            my $name = shift @$route;
            my $type = shift @$route;
            my $value = param($name);
            $p->{$name} = $value if defined $value && (!defined($type) || $value =~ /^$type$/);
        }
    }

    ($fn, $p);
}

1;
