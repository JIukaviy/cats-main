package CATS::Problem;

#use lib '..';
use strict;
use warnings;
use Encode;

use CATS::Constants;
use CATS::Misc qw(:all);
#use FileHandle;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use XML::Parser::Expat;

my $default_mlimit = 200;

my ($stml, $cid, $pid, $zip, $import_log, $zip_archive, $old_title,
    %problem, %objects, %solution, %checker,
    %generator, %generator_range, %module,
    %picture, %test, %test_range, %sample,
    %test_rank_array, %sample_rank_array,
    %keyword, %tag_import,
    $statement, $constraints,
    $inputformat, $outputformat, $user_checker);

my %stml_tags = (
    'ProblemStatement' => \$statement, 
    'ProblemConstraints' => \$constraints,
    'InputFormat' => \$inputformat, 
    'OutputFormat' => \$outputformat 
);

my $module_types = {
    'checker' => $cats::checker_module,
    'solution' => $cats::solution_module,
    'generator' => $cats::generator_module,
};

sub note($)
{
    $import_log .= $_[0];
}


sub warning($) 
{
    my $m = 'Warning: ' . shift;
    $import_log .= $m;
}


sub error($) 
{
    $import_log .= 'Error: ' . $_[0];
    die "Unrecoverable error\n";
}


sub start_stml_element
{
    my ($stream, $el, %atts) = @_;
    
    $$stream .= "<$el";
    if ($el eq 'img' && !$atts{'picture'})
    {
        warning "Picture not defined in img element\n";
    }
    for my $name (keys %atts)
    {
        $$stream .= qq~ $name="$atts{$name}"~;
    }
    $$stream .= '>';
}


sub end_element
{
    my ($stream, $el) = @_;    
    $$stream .= "</$el>";
}


sub text
{
    my ($stream, $text) = @_;    
    $$stream .= escape_html $text;
}


sub read_member
{
    my $member = shift;

    my ($data, $status, $buffer) = "";
    
    $member->desiredCompressionMethod(COMPRESSION_STORED);
    $status = $member->rewindData();
    error "error $status" unless ($status == AZ_OK);

    while (!$member->readIsDone())
    {
        ($buffer, $status) = $member->readChunk();
        error "error $status" if ($status != AZ_OK && $status != AZ_STREAM_END);
        $data .= $$buffer;
    }
    $member->endRead();

    return $data;    
}


sub required_attributes
{
    my ($el, $attrs, $names) = @_;
    for (@$names)
    {
        defined $attrs->{$_}
            or error "$el.$_ not specified\n";
    }
}


# 1 ������
sub stml_text
{
    my ($p, $text) = @_;
    if ($stml) { 
        text($stml, $text); 
    }  
}


sub user_checker_found
{
    if (defined $user_checker)
    {
        error "Found several checkers\n";
    }
    $user_checker = 1;
}


sub parse_problem
{
    my ($p, $el, %atts) = @_;

    if ($stml)
    {
        start_stml_element($stml, $el, %atts); 
        return; 
    }

    if (defined $stml_tags{$el})
    {
        $stml = $stml_tags{$el};
    }
    
    if ($el eq 'Problem')
    {
        required_attributes($el, \%atts, ['title', 'lang', 'tlimit', 'inputFile', 'outputFile']);

        defined $atts{'mlimit'}
            or warning "Problem.mlimit not specified. default: $default_mlimit\n";

        %problem = (
            'title' => $atts{'title'},
            'lang' => $atts{'lang'},
            'time_limit' => $atts{'tlimit'},
            'memory_limit' => ($atts{'mlimit'} or $default_mlimit),
            'difficulty' => $atts{'difficulty'},
            'author' => $atts{'author'},
            'input_file' => $atts{'inputFile'},
            'output_file' => $atts{'outputFile'},       
            'std_checker' => $atts{'stdChecker'},
            'max_points' => $atts{'maxPoints'}
        );
        if ($old_title && $problem{title} ne $old_title)
        {
            error "Problem was renamed unexpectedly, old title: $old_title\n";
        }
    }
}


sub problem_bind
{
    my ($c) = @_;
    my $i = \$_[1];
    
    $c->bind_param($$i++, $cid);
    $c->bind_param($$i++, $problem{'title'});
    $c->bind_param($$i++, $problem{'lang'});
    $c->bind_param($$i++, $problem{'time_limit'});
    $c->bind_param($$i++, $problem{'memory_limit'});
    $c->bind_param($$i++, $problem{'difficulty'});
    $c->bind_param($$i++, $problem{'author'});
    $c->bind_param($$i++, $problem{'input_file'});
    $c->bind_param($$i++, $problem{'output_file'});
    $c->bind_param($$i++, $statement, { ora_type => 113 });
    $c->bind_param($$i++, $constraints, { ora_type => 113 });
    $c->bind_param($$i++, $inputformat, { ora_type => 113 });
    $c->bind_param($$i++, $outputformat, { ora_type => 113 });
    $c->bind_param($$i++, $zip_archive, { ora_type => 113 });
    $c->bind_param($$i++, $problem{'std_checker'});
    $c->bind_param($$i++, $uid);
    $c->bind_param($$i++, $problem{'max_points'});
}


sub problem_insert
{
    my ($p, $el) = @_;

    if (defined $stml_tags{$el}) { $stml = 0; }

    if ($stml) { end_element($stml, $el); return; }     

    if ($el eq 'Problem')
    {   
        my $c = $dbh->prepare(qq~
            INSERT INTO problems (
                id, contest_id, title, lang, time_limit, memory_limit, difficulty, author, 
                input_file, output_file, statement, pconstraints, input_format, output_format, 
                zip_archive, upload_date, std_checker, last_modified_by, max_points
            ) VALUES (
                ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,CATS_SYSDATE(),?,?,?
            )~
        );

        my $i = 1;
        $c->bind_param($i++, $pid);
        problem_bind($c, $i);
        $c->execute;

    }
}


sub problem_update
{
    my ($p, $el) = @_;

    if (defined $stml_tags{$el}) { $stml = 0; }

    if ($stml) { end_element($stml, $el); return; }     

    if ($el eq 'Problem')
    {
        $dbh->do(qq~DELETE FROM pictures WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM samples WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM tests WHERE problem_id=?~, {}, $pid) && 
        $dbh->do(qq~DELETE FROM problem_sources WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM problem_sources_import WHERE problem_id=?~, {}, $pid) &&
        $dbh->do(qq~DELETE FROM problem_keywords WHERE problem_id=?~, {}, $pid) ||
           error "Couldn't update problem\n";
    
        my $c = $dbh->prepare(qq~
            UPDATE problems 
            SET
                contest_id=?, title=?, lang=?, time_limit=?, memory_limit=?, difficulty=?, author=?, 
                input_file=?, output_file=?, 
                statement=?, pconstraints=?, input_format=?, output_format=?, 
                zip_archive=?, upload_date=CATS_SYSDATE(), std_checker=?, last_modified_by=?,
                max_points=?, hash=NULL
            WHERE id = ?~
        );

        my $i = 1;
        problem_bind($c, $i);
        $c->bind_param($i++, $pid);
        $c->execute;
    }
} 


# 2 ������
sub set_object_id 
{
    my ($name, $id) = @_;
    $name or return; 
    error "Duplicate object reference: '$name'\n" if defined $objects{$name};
    $objects{$name} = $id;
}


sub get_object_id 
{
    my ($name, $tag) = @_;
    defined $name or return undef;
    error "Undefined object reference: '$name' in '$tag'\n" unless defined $objects{$name};
    return $objects{$name};
}


sub get_source_de 
{
    my $fname = shift;

    my ($vol, $dir, $file_name, $name, $ext) = split_fname($fname);
    
    my $c = $dbh->prepare(qq~SELECT id, code, description, file_ext FROM default_de~);
    $c->execute;    
    while (my ($did, $code, $description, $file_ext) = $c->fetchrow_array)
    {
        my @ext_list = split(/\;/, $file_ext);

        for my $i (@ext_list) {
            if ($i ne '' && $i eq $ext) {
                return ($did, $description);
            }
        }
    }
    
    return undef;
}


sub get_de_id 
{
    my $code = shift;
    my $path = shift;
    if (defined $code)
    {
        my $did = $dbh->selectrow_array(qq~SELECT id FROM default_de WHERE code=?~, {}, $code);
        unless (defined $did) {
            error "Unknown de code: '$code' for source: '$path'\n";
        }
        return $did;
    } 
    else 
    {
        my ($did, $de_desc) = get_source_de($path);
        if (defined $did) {
            note "Detected de: '$de_desc' for source: '$path'\n";
            return $did;
        }
        else {
            error "Can't detect de for source: '$path'\n";
        }
    }
    return undef;
}
                    

sub interpolate_rank { apply_test_rank(@_); }

sub apply_test_rank
{
    my ($v, $rank) = @_;
    $v ||= '';
    $v =~ s/%n/$rank/g;
    $v =~ s/%0n/sprintf("%02d", $rank)/eg;
    $v;
}


sub read_member_named
{
    my %p = @_;
    my $member = $zip->memberNamed($p{name}) 
        or error "Invalid $p{kind} reference: '$p{name}'\n";

    return
        ('src' => read_member($member), 'path' => $p{name});
}


sub create_generator
{
    my %p = @_;
    
    my $id = new_id;
    set_object_id($p{name}, $id);

    return (  
        'id' => $id,
        read_member_named(name => $p{src}, kind => 'generator'),
        'de_code' => $p{de_code},
        'outputFile' => $p{'outputFile'},
    );
}


sub parse_problem_content
{
    my ($p, $el, %atts) = @_;

    if ($el eq 'Picture')
    {
        required_attributes($el, \%atts, ['src', 'name']);

        my @p = split(/\./, $atts{'src'});
        my $ext = $p[-1];
        error "Invalid image extension\n" if $ext eq '';
        
        %picture = (
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'picture'),
            'name' => $atts{'name'},
            'ext' => $ext
        )
    }

    if ($el eq 'Solution')
    {
        required_attributes($el, \%atts, ['src', 'name']);

        my $id = new_id;
        set_object_id($atts{'name'}, $id);

        %solution = (   
            'id' => $id,
            read_member_named(name => $atts{'src'}, kind => 'solution'),
            'de_code' => $atts{'de_code'},
            'guid' => $atts{export},
            'checkup' => $atts{'checkup'},
        )
    }

    if ($el eq 'Checker')
    {
        required_attributes($el, \%atts, ['src']);

        my $style = $atts{'style'} || 'legacy';
        for ($style)
        {
            /^legacy$/ && do { warning "Legacy checker found!\n"; last; };
            /^testlib$/ && last;
            error "Unknown checker style (must be either 'legacy' or 'testlib')\n";
        }
        
        user_checker_found();
        %checker = (    
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'checker'),
            'de_code' => $atts{'de_code'},
            'guid' => $atts{export},
            'style' => $style
        )
    }

    if ($el eq 'Generator')
    {
        required_attributes($el, \%atts, ['src', 'name']);
        %generator = create_generator(%atts);
    }

    if ($el eq 'GeneratorRange')
    {
        required_attributes($el, \%atts, ['src', 'name', 'from', 'to']);
        %generator_range = (  
            'path' => $atts{'src'},
            'de_code' => $atts{'de_code'},
            'elements' => {}
        );
        for ($atts{'from'} .. $atts{'to'})
        {
            $generator_range{'elements'}->{$_} = { create_generator(
                name => interpolate_rank($atts{name}, $_),
                src => interpolate_rank($atts{src}, $_),
                guid => interpolate_rank($atts{export}, $_),
                de_code => $atts{de_code},
                outputFile => $atts{outputFile},
            ) };
        }
    }

    if ($el eq 'Module')
    {
        required_attributes($el, \%atts, ['src', 'de_code', 'type']);

        exists $module_types->{$atts{'type'}}
            or error "Unknown module type: $atts{'type'}\n";
        %module = (
            'id' => new_id,
            read_member_named(name => $atts{'src'}, kind => 'module'),
            'de_code' => $atts{'de_code'},
            'guid' => $atts{export},
            'type' => $atts{'type'},
            'type_code' => $module_types->{$atts{'type'}},
        );
    }

    if ($el eq 'Import')
    {
        required_attributes($el, \%atts, ['guid']);
        %tag_import = (guid => $atts{guid});
        my $t = $atts{type};
        if (defined $t)
        {
            exists $module_types->{$t}
                or error "Unknown import source type: $t\n";
            $tag_import{type} = $module_types->{$t};
        }
    }

    if ($el eq 'Test')
    {
        required_attributes($el, \%atts, ['rank']);

        for ($atts{'rank'})
        {
            /^\d+$/ or error "Bad rank: '$_'\n";
            !defined $test_rank_array{$_}
                or error "Duplicate test $_\n";
            $test_rank_array{$_} = 1;
        }

        %test = (
            'rank' => $atts{'rank'},
            'points' => $atts{'points'},
            'in' => 1
        );

    }

    if ($el eq 'TestRange')
    {
        required_attributes($el, \%atts, ['from', 'to']);

        $atts{'from'} <= $atts{'to'}
            or error 'TestRange.from > TestRange.to';

        %test_range = (
            'from' => $atts{'from'},
            'to' => $atts{'to'},
            'points' => $atts{'points'},
            'in' => 1
        );

        for ($atts{'from'}..$atts{'to'})
        {
            !defined $test_rank_array{$_}            
                or error "Duplicate test $_\n";
            $test_rank_array{$_} = 1;
        }
    }   


    if ($el eq 'In' && $test{in})
    {
        if (defined $atts{'src'})
        {
            #$test{'in_file'} = read_member_named(name => $atts{'src'}, kind => 'test input file'),
            my $member = $zip->memberNamed($atts{'src'});
            error "Invalid test input file reference: '$atts{'src'}'\n" if (!defined $member);
            $test{'in_file'} = read_member($member);
        }
        elsif (defined $atts{'use'})
        {
            $test{'generator_id'} = get_object_id($atts{'use'}, $el);
            $test{'param'} = $atts{'param'};
        }
        else {
            error "Test input file not specified for test $test{rank}\n";
        }
    }

    if ($el eq 'Out' && $test{in})
    {
        if (defined $atts{'src'})
        {
            my $member = $zip->memberNamed($atts{'src'}) 
                or error "Invalid test output file reference: '$atts{'src'}'\n";
            $test{'out_file'} = read_member($member);
        }
        elsif (defined $atts{'use'})
        {
            $test{'std_solution_id'} = get_object_id($atts{'use'}, $el);
        }
        else
        {
            error "Test output file not specified $test{rank}\n";
        }
    }       

    if ($el eq 'In' && $test_range{in})
    {       
        if (defined $atts{'src'}) 
        {
            $test_range{'in_src'} = $atts{'src'};
        }
        elsif (defined $atts{'use'})
        {
            $test_range{'generator'} = $atts{'use'};            
            $test_range{'param'} = $atts{'param'};
        }
        else {
            error "Test input file not specified for test range\n";
        }
    }


    if ($el eq 'Out' && $test_range{in})
    {
        if (defined $atts{'src'})
        {
            $test_range{'out_src'} = $atts{'src'};
        }
        elsif (defined $atts{'use'})
        {
            $test_range{'std_solution'} = $atts{'use'};
        }
        else
        {
            error "Test output file not specified for test range\n";
        }
    }       


    if ($el eq 'Sample')
    {
        required_attributes($el, \%atts, ['rank']);

        if (defined $sample_rank_array{$atts{'rank'}}) {            
            error "Duplicate sample $atts{'rank'}\n";
        }

        %sample = (
            'sample_id' => new_id,
            'rank'  => $atts{'rank'},
        );

        $sample_rank_array{$atts{'rank'}} = 1;
    }   

    if ($el eq 'SampleIn')
    {
        $sample{'in'} = 1;
        $sample{'in_file'} = '';
    }

    if ($el eq 'SampleOut')
    {
        $sample{'out'} = 1;
        $sample{'out_file'} = '';
    }

    if ($el eq 'Keyword')
    {
        %keyword = ('code' => $atts{'code'});
    }
}


sub problem_content_text 
{
    my ($p, $text) = @_;

    if ($sample{'in'})
    {
        $sample{'in_file'} .= $text;
    }

    if ($sample{'out'})
    {
        $sample{'out_file'} .= $text;
    }
}

sub insert_problem_source
{
    my %p = @_;
    my $s = $p{source_object} or die;

    if ($s->{'guid'})
    {
        if (my $dup_id = $dbh->selectrow_array(qq~
            SELECT problem_id FROM problem_sources WHERE guid = ?~, undef, $s->{'guid'})
        )
        {
            warning "Duplicate guid with problem $dup_id\n";
        }
    }
    my $c = $dbh->prepare(qq~
        INSERT INTO problem_sources (
            id, problem_id, de_id, src, fname, stype, input_file, output_file, guid
        ) VALUES (?,?,?,?,?,?,?,?,?)~);

    $c->bind_param(1, $s->{'id'});
    $c->bind_param(2, $pid);
    $c->bind_param(3, get_de_id($s->{'de_code'}, $s->{'path'}));
    $c->bind_param(4, $s->{'src'}, { ora_type => 113 });
    $c->bind_param(5, $s->{'path'});
    $c->bind_param(6, $p{source_type});
    $c->bind_param(7, $s->{'inputFile'});
    $c->bind_param(8, $s->{'outputFile'});
    $c->bind_param(9, $s->{'guid'});
    $c->execute;

    my $g = $s->{guid} ? ", guid=$s->{guid}" : '';
    note "$p{type_name} '$s->{path}' added$g\n";
}


sub insert_problem_content
{
    my ($p, $el) = @_;

    if ($el eq 'Problem')
    {
        my $std_checker = $problem{'std_checker'};
        !defined $user_checker || !defined $std_checker
            or error "User checker and standart checker specified\n";

        defined $user_checker || defined $std_checker
            or error "No checker specified\n";

        note "Checker: $problem{'std_checker'}\n" if $std_checker;
    }
    elsif ($el eq 'Generator')
    {
        insert_problem_source(
            source_object => \%generator, source_type => $cats::generator, type_name => 'Generator');
        %generator = ();
    }
    elsif ($el eq 'GeneratorRange')
    {
        for (values %{$generator_range{'elements'}})
        {
            insert_problem_source(
                source_object => $_, source_type => $cats::generator, type_name => 'Generator');
        }
        %generator_range = ();
    }
    elsif ($el eq 'Solution')
    {
        insert_problem_source(
            source_object => \%solution, type_name => 'Solution',
            source_type =>
                defined $solution{'checkup'} && $solution{'checkup'} == 1 ?
                $cats::adv_solution : $cats::solution);
        %solution = ();
    }
    elsif ($el eq 'Checker')
    {
        insert_problem_source(
            source_object => \%checker, type_name => 'Checker',
            source_type => ($checker{style} eq 'legacy' ? $cats::checker : $cats::testlib_checker)
        );
        %checker = ();
    }
    elsif ($el eq 'Module')
    {
        insert_problem_source(
            source_object => \%module, source_type => $module{'type_code'},
            type_name => "Module for $module{type}");
        %module = ();
    }
    elsif ($el eq 'Import')
    {
        $dbh->do(q~
            INSERT INTO problem_sources_import (problem_id, guid) VALUES (?, ?)~, undef,
            $pid, $tag_import{guid});
        my ($src_id, $stype) = $dbh->selectrow_array(qq~
            SELECT id, stype FROM problem_sources WHERE guid = ?~, undef, $tag_import{guid});
        if ($src_id)
        {
            if ($tag_import{type})
            {
                $stype == $tag_import{type} || $cats::source_modules{$stype} == $tag_import{type}
                    or error "Import type check failed for guid='$tag_import{guid}' ($tag_import{type} vs $stype)\n";
            }
            user_checker_found() if $stype == $cats::checker || $stype == $cats::testlib_checker;
            note "Imported source from guid='$tag_import{guid}'\n";
        }
        else
        {
            warning "Import source not found for guid='$tag_import{guid}'\n";
        }
    }
    elsif ($el eq 'Picture')
    {
        my $c = $dbh->prepare(qq~
            INSERT INTO pictures(id, problem_id, extension, name, pic)
                VALUES (?,?,?,?,?)~);

        $c->bind_param(1, $picture{'id'});     
        $c->bind_param(2, $pid);
        $c->bind_param(3, $picture{'ext'});
        $c->bind_param(4, $picture{'name'} );
        $c->bind_param(5, $picture{'src'}, { ora_type => 113 });
        $c->execute;

        note "Picture '$picture{'path'}' added\n";
        %picture = ();
    }
    elsif ($el eq 'Test')
    {
        my $c = $dbh->prepare(qq~
            INSERT INTO tests (
                problem_id, rank, generator_id, param, std_solution_id, in_file, out_file, points
            ) VALUES (?,?,?,?,?,?,?,?)~
        );

        $c->bind_param(1, $pid);
        $c->bind_param(2, $test{'rank'});
        $c->bind_param(3, $test{'generator_id'});
        $c->bind_param(4, $test{'param'});
        $c->bind_param(5, $test{'std_solution_id'} );
        $c->bind_param(6, $test{'in_file'}, { ora_type => 113 });
        $c->bind_param(7, $test{'out_file'}, { ora_type => 113 });
        $c->bind_param(8, $test{'points'});
        eval { $c->execute; };
        if ($@) {
            error "Can not add test $test{'rank'}: $@";
        }

        note "Test $test{'rank'} added\n";
        %test = ();
    }
    elsif ($el eq 'TestRange')
    {
        for my $rank ($test_range{from}..$test_range{to})
        {
            my $in_file = undef;
            if (defined $test_range{in_src})
            {
                my $in_src = apply_test_rank($test_range{in_src}, $rank);

                my $member = $zip->memberNamed($in_src)
                    or error "Invalid test input file reference: '$in_src'\n";
                $in_file = read_member($member);            
            }        

            my $out_file = undef;
            if (defined $test_range{out_src})
            {
                my $out_src = apply_test_rank($test_range{out_src}, $rank);

                my $member = $zip->memberNamed($out_src)
                    or error "Invalid test output file reference: '$out_src'\n";
                $out_file = read_member($member);
            }
               
            my $param = apply_test_rank($test_range{'param'}, $rank);
            my $gen = apply_test_rank($test_range{'generator'}, $rank);
            my $sol = apply_test_rank($test_range{'std_solution'}, $rank);
            
            my $c = $dbh->prepare(qq~
                INSERT INTO tests (
                    problem_id, rank, generator_id, param, std_solution_id, in_file, out_file, points
                ) VALUES (?,?,?,?,?,?,?,?)~
            );
               
            $c->bind_param(1, $pid);
            $c->bind_param(2, $rank);
            $c->bind_param(3, $gen ? get_object_id($gen, $el) : undef);
            $c->bind_param(4, $param);
            $c->bind_param(5, $sol ? get_object_id($sol, $el) : undef);
            $c->bind_param(6, $in_file, { ora_type => 113 });
            $c->bind_param(7, $out_file, { ora_type => 113 });
            $c->bind_param(8, $test_range{points});
            $c->execute;

            note "Test $rank added\n";
        }
        %test_range = ();
    }
    elsif ($el eq 'SampleIn')
    {
        delete $sample{'in'};
    }
    elsif ($el eq 'SampleOut')
    {
        delete $sample{'out'};
    }
    elsif ($el eq 'Sample')
    {
        my $c = $dbh->prepare(qq~
            INSERT INTO samples (problem_id, rank, in_file, out_file)
            VALUES (?,?,?,?)~
        );
            
        $c->bind_param(1, $pid);
        $c->bind_param(2, $sample{'rank'});
        $c->bind_param(3, $sample{'in_file'}, { ora_type => 113 });
        $c->bind_param(4, $sample{'out_file'}, { ora_type => 113 });
        $c->execute;

        note "Sample test $sample{'rank'} added\n";

        %sample = ();
    }
    elsif ($el eq 'Keyword')
    {
        my ($keyword_id) = $dbh->selectrow_array(q~
            SELECT id FROM keywords WHERE code = ?~, undef, $keyword{code});
        if ($keyword_id)
        {
            $dbh->do(q~
                INSERT INTO problem_keywords (problem_id, keyword_id) VALUES (?, ?)~, undef,
                $pid, $keyword_id);
            note "Keyword added: $keyword{code}\n";
        }
        else
        {
            warning "Unknown keyword: $keyword{code}\n";
        }
        %keyword = ();
    }
} 


sub clear_globals 
{
    $stml = 0;
    $import_log = '';
    $zip = undef;
    $user_checker = undef;

    %problem = ();
    %objects = ();
    %solution = ();
    %checker = ();
    %generator = ();
    %generator_range = ();
    %module = ();
    %picture = ();
    %test = ();
    %test_range = ();
    %test_rank_array = ();
    %sample_rank_array = ();
    %keyword = ();

    $statement = $constraints = $inputformat = $outputformat = undef;
}


sub verify_test_order
{
    my @order = sort { $a <=> $b } keys %test_rank_array
        or error "Empty test set\n";

    for (1..@order) {           
        if ($order[$_ - 1] != $_) {
            error "Missing test #$_\n";
        }
    }   

    @order = sort { $a <=> $b } keys %sample_rank_array;
    for (1..@order) {
        if ($order[$_ - 1] != $_) {
            error "Missing sample #$_\n";
        }
    }
}


sub import_problem
{
    my ($fname, $replace);

    $fname = shift;
    $cid = shift;    
    $pid = shift;
    $replace = shift;
    $old_title = shift;

    clear_globals;
    eval 
    {
        unless (open FILE, "<$fname") 
        {
            error "open '$fname' failed: $!\n"; 
            return (undef, $import_log);
        };
          
        binmode(FILE, ':raw');

        $zip_archive = '';
        
        my $buffer;
        while (sysread(FILE, $buffer, 4096)) {
            $zip_archive .= $buffer;
        }
    
        close FILE;    
                    
        $zip = Archive::Zip->new();
        error "read '$fname' failed -- probably not a zip archive\n"
            unless ($zip->read($fname) == AZ_OK);

        my @xml_members = $zip->membersMatching('.*\.xml');

        error "*.xml not found\n" if (!@xml_members);
        error "found severl *.xml in archive\n" if (@xml_members > 1);

        my $member = $xml_members[0];
        my $xml_doc = read_member($member);

        $stml = 0;
    
        # ������ ������
        my $parser = new XML::Parser::Expat;

        if (!$replace) {
            $parser->setHandlers(
                    'Start' => \&parse_problem,
                    'End'   => \&problem_insert,
                    'Char'  => \&stml_text);
            $parser->parse($xml_doc); 
        } 
        else
        {
            $parser->setHandlers(
                    'Start' => \&parse_problem,
                    'End'   => \&problem_update,
                    'Char'  => \&stml_text);
            $parser->parse($xml_doc);   
        } 

        # ������ ������
        $parser = new XML::Parser::Expat;
        $parser->setHandlers(
                    'Start' => \&parse_problem_content,
                    'End'   => \&insert_problem_content,
                    'Char'  => \&problem_content_text);
        $parser->parse($xml_doc);

        verify_test_order;
    };

    #print $@;

    my $res;    
    if ($@ eq '') {
        $dbh->commit;
        note "Success\n";
        $res = 0;
    }
    else {
        $dbh->rollback;
        $res = -1;
        note "Import failed: $@\n";
    }

    return ($res, $import_log);
}

1;