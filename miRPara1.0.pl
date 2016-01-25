#! /usr/bin/perl -w
#mirpara.pl
use warnings;
use strict;
use Bio::Seq;#read and output sequences
use Bio::SeqIO;#read and output sequences
use XML::Simple;
use Data::Dumper;
use Getopt::Long;
use Algorithm::SVM;
use Algorithm::SVM::DataSet;
use File::chdir;#to change the perl environment

my $abname="noname";
my $species="";
my $limit=60;
my %options;
my $path;
my $m;#tmp number
my %mirbase;#for blast message
my @basedata;
my @base;
my $level=7;
my $inputfile="";
my $range;#xml range object
my @hpname;
GetOptions \%options, 'version|v' => sub { version('miRPara.pl') },
						'help|h' => sub { usage() },
						'name|n=s' => \$abname,
						'species|s=s' => \$species,
						'level|l=i'=>\$level,
						'prilengthlimit|lmt=i' => \$limit or die $!;
$inputfile=shift;
if (length($inputfile) eq 0) {
   print STDERR "Error: data not specified\nRun 'miRPara.pl -h' for help\n";
    exit;
}
$path=path($inputfile);
if (index("overallanimalplantvirus",$species) eq "-1"){#to check the species
	print "Please provide right species name!!\n";
	die;
}
if ($species eq ""){#default species
	$species ="overall";
}
if (index($inputfile,'.nm') ne "-1"){
   $abname=~ s/$path//;
   $abname=~ s/\_hairpin.nm//;
   $abname=~ s/\_.nm//;
   if (index($inputfile,"\_hairpin.nm") ne "-1"){
	  open (IN,$inputfile);
	  @hpname=<IN>;
	  close IN;
   }
   else{
	  @hpname=glob "$path*\.fas";
   my $hpname;
   foreach (@hpname){
	  $_=~ s/$path//g;
	  $_=~ s/\.fas//g;
	  $hpname.="$_\n";
   }
	open (NAME,">$path$abname\_hairpin.nm");#output the name infor
	print NAME $hpname;
	close NAME;
   }
	goto step2;
}
elsif (index($inputfile,'.dat') ne "-1"){
	$abname=$inputfile;
	$abname=~ s/$path//;
	$abname=~ s/\.dat//;
   goto step3;
}
else{
   goto step1;
}
step1:
if ($abname eq "noname"){
   $abname=seqsplit($path,$inputfile,$abname,6000,500);
}
else {
   seqsplit($path,$inputfile,$abname,6000,500);
}
callunafd($path,$abname,'-l');
#readlongfile
readlongfile($path,$abname,$limit);
#call unafold
step2:
#goto p;
callunafd($path,$abname,'-s');
$range=XMLin("./range.pmt");
candidate($path,$abname,$species,$range);
#prepare the final result file
#pmt2svmdata
step3:
predict($path,$abname,$species,$level);
open (IN,"mirbase.dat");
@basedata=<IN>;
close IN;
foreach (@basedata){
   $_=~ s/\n+//g;
   if ($_ ne ""){
	  @base=split(":",$_);
	  $mirbase{lc($base[0])}="$base[1]";
   }
}
out($path,$abname,$level,%mirbase);
print "\nAll Done.\n";
sub usage () {
    print <<EOF;
Usage: miRPara.pl [options] file [file]

Options:
-V, --version
-h, --help
-n, --name=<abbreviated name (3 characters) of the species>
-s, --species=<overall, animal, plant or virus> (defaults as overall)
-l, --Level=<1..10>(defaults to 7)
-lmt, --prilengthlimit=<limit to the pri-miRNA length> (defaults to 60)

File:
--Long Sequence file (*.fas, *.fasta, *.gb)
	To predict miRNAs from a long sequence
--Short Sequence files (*_hairpin.nm)
	TO cansider each samll sequence as a hairpin and to test if there any
	miRNAs in it.
--SVM data file (*.dat)
	To repredict with different levels

Parameters discription:
--Length (nt or bp)
	Length of pri-miRMA, pre-miRNA and miRNA (nt)
	Length of Basal Segment, Lower Stem, Upper Stem and Top Stem (bp)
	Length of Terminal Loop (nt)
--GC Content (%)
	GC Content of pri-miRMA, pre-miRNA and miRNA
--Minimal Free Energy (MFE) (kcal/mol)
	MFE of pri-miRMA, pre-miRNA
	Minimal Free Energy Index (MFEI) of pri-miRMA, pre-miRNA
--Nucleotide Content (%)
	'A' Content of pri-miRMA, pre-miRNA and miRNA
	'U' Content of pri-miRMA, pre-miRNA and miRNA
	'C' Content of pri-miRMA, pre-miRNA and miRNA
	'G' Content of pri-miRMA, pre-miRNA and miRNA
--Base Pairs (bp)
	Base Pairs of pri-miRMA, pre-miRNA and miRNA
--Internal Loop (nt)
	The biggest bulge of pri-miRMA, pre-miRNA and miRNA
	The biggest bulge of Lower Stem and Top Stem
--Unpaired Bases (nt)
	Unpaired Bases of pri-miRMA, pre-miRNA and miRNA
	Unpaired Bases of Lower Stem and Top Stem
--Unpaired Rate (%)
	Unpaired Rate of pri-miRMA, pre-miRNA and miRNA
	Unpaired Rate of Lower Stem and Top Stem
--G:U Wobbles (bp)
	GU of pri-miRMA, pre-miRNA and miRNA
--Strand
	Strand of miRNAs
--First Base
	First Base of miRNA
--Stability
	Stability of miRNA
--Overhang
	3' 2-nt overhang (default)
	Penultimate Position of overhang
	Terminal Nucleotide of overhang

EOF
print 'Report bugs to raynere@wh.iov.cn or weasteam@gmail.com', "\n";
    exit;
}
sub version ($) {
	print "\n";
    print "$_[0] (miRPare) 1.0 Beta\n";
    print "By Yonggan Wu and Simon Rayner\n";
    print "Copyright (C) 2008\n";
    print "Wuhan Institute of Virology, Chinese Academic of Science.\n";
    print "Wuhan, 430071, China\n\n";
    exit;
}
sub seqsplit{#split sequence into small sequences
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The seqsplit was used to split the given sequence into small ones
	#===========Usage: seqsplit($path,$inputfile,$abname,splitlength,overlap)
	#===========The $abname will be return to the main program.
	#===========The *_splitseq.nm will be created with the created seq (fasta format)
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $path;
	my $filename;#the file name
	my $splitlength;#the output length
	my $overlap;#the overlap length
	my $seq_obj;#the sequence object
	my $seq;#the sequence of the file
	my $seqlength;#the length of the input sequences
	my $id;#the id of the sequence
	my $seqname;#the name of new sequences
	my $splitseq;#teh splited sequences
	my $splitname;#the name of splited sequences
	my $split_obj;#the sequence of splited sequences
	my $outputseq;#the sequence of output sequences
	my $start;#start of a short sequence
	my $end;#end of a short sequence
	($path,$filename,$id,$splitlength,$overlap)=@_;#input the file
	$seq_obj = Bio::SeqIO->new(-file => "$filename");
	$seq = $seq_obj->next_seq;#get the sequence
	$seqlength = $seq->length();#get the length of the whole sequence
	if ($id eq "noname") {
		$id=$seq->display_id();#get the name of the species name
	}
	if ($id eq "") {#incase of no name
		$id="noname";#get the name of the species name
	}
	$start=1;#start of a short sequence
	$end = $start -1 + $splitlength;#end of a short sequence
	if ($seqlength<=$splitlength) {#if the sequence if smaller than the span-$splitlength, output the file directly
		$seqname="$id\_1-$seqlength\.fas";
		$splitseq=$seq->subseq(1,$seqlength);
		$split_obj = Bio::Seq->new(-seq => $splitseq,
				-display_id => $seqname);
		$outputseq = Bio::SeqIO->new(-file => ">$path$seqname",
				-format => 'fasta' );
		$outputseq->write_seq($split_obj);
		$splitname ="$id\_1-$seqlength\n";
	}
	else {#if the sequence is longer than the span-$splitlength, be cutted with $overlap overlapped
		while ($start <= $seqlength) {
			if ($end >=$seqlength) {#in the case that the last loop
				$end = $seqlength;
			}
			$seqname="$id\_$start-$end\.fas";#define a fine name of new seq
			$splitseq=$seq->subseq($start,$end);
			$split_obj = Bio::Seq->new(-seq => $splitseq,
					-display_id => $seqname);#extract the seq
			$outputseq = Bio::SeqIO->new(-file => ">$path$seqname",
					-format => 'fasta' );#print the seq
			$outputseq->write_seq($split_obj);
			$splitname .="$id\_$start-$end\n";#collect the name
			if ($end !=$seqlength) {#redefine the start and the end
				$start = $end -$overlap +1;
				$end = $start -1 + $splitlength;
			}
			else {#in the case that the last loop
				$start = $end +1;
			}
		}
	}
	open(NAME, ">$path$id\_splitseq.nm");#output the command of the sequence
	print NAME ($splitname);
	close NAME;
	return $id;
}
sub callunafd{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The callunafd was used to call unafold.pl to generate the second
	#			structure and minimal free energy.
	#===========Usage: seqsplit($path,$abname,parameter)
	#			-l for the long file *_splitseq.nm
	#			-s for the short file *_hairpin.nm
	#			-pre for the pre-miRNAs
	#===========The the ct2out will be called at the same time to generate the *.out
	#===========The *.out file will be output and other files from unafold.pl will be deleted
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $path;
	my $abname;
    my $parameter;
    my $filename;
    my @seqname;
	my $tmpname;
    ($path,$abname,$parameter)=@_;#-l for the long file, and -s for the small file
    if ($parameter eq "-l"){
	$filename="$path$abname\_splitseq.nm";#get the name of name file
    open (NAME,"$filename");#read the name of the long sequences
    @seqname=<NAME>;
    close NAME;
    }
    if ($parameter eq "-s"){
	$filename="$path$abname\_hairpin.nm";#get the name of name file
    open (NAME,$filename);#read the name of the long sequences
    @seqname=<NAME>;
    close NAME;
    }
    if ($parameter eq "-pre"){
	  $seqname[0]="tmp\n";#get the name of name file
    }
	my $ctname;
	foreach (@seqname) {#run unafold
		$_=~ s/\n//g;
		system "cp $path$_\.fas $path$_\_tmp.fas";
		{
		local $CWD = "$path";#change the envirioment directory
		system "UNAFold.pl $_\_tmp.fas";
		$ctname="$_\_tmp.fas_1.ct";#get the ct file name
		system "pwd";
		system "ct2out <$ctname> $_\.out";#run ct2out
		system "rm $_\_tmp.fas*";
		}
	}
}
sub readlongfile{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The readlongfile was used to get all hairpin seq from *.out
	#===========Usage: readlongfile($path,$abname,$limit)
	#			--limit the length limit of prilength
	#===========The *_splitseq.nm is need for right information
	#===========The sequence will be output as fasta format
	#			and a *_hairpin.nm will also be output
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#format readlongfile(length)
	my $path;
	my $abname;
	my $prilength;
	($path,$abname,$prilength)=@_;
	my $name="$path$abname\_splitseq.nm";#get the name of name file
	#my $name="$abname\_splitseq.nm";#get the name of name file
	open (NAME,$name);#read the name of the long sequences
	my @seqname=<NAME>;
	close NAME;
	#chop(@seqname);#delete the \n
	my $id=$seqname[0];#the the id from the name
	$id=~ s/_1-[0-9]+//;
	$id=~ s/\n//;
	my $serial=1;#the number of hairpins
	my $outname;#the name of *.out files
	my @data;#the data of the *.out file
	my $line;#the number of line
	my $m;#tmp number
	my $n;#tmp number
	my $string;#tmp string
	my %hairpin;#hairpin structure
	my $rp=0;#whether a sequence from repeat or overlap reagion
	my $seq;#each small sequence
	my @sequence;#collection of all seq, to avoid replicate
	my $hpname="";#the name of hairpin
	if ($prilength eq ""){
		$prilength = 60;#<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	}
	foreach (@seqname){
		$_=~ s/\n//g;
		$outname=$_."\.out";
		open (DATA,"$path$outname");#read the data of *.out file
		@data=<DATA>;
		close DATA;
		$line=5;
		until (substr($data[$line-1],0,1) eq "_"){#"_", the end signal
			$hairpin{1}=$data[$line];#add data to each hairpin segment
			$hairpin{2}=$data[$line+1];
			$hairpin{3}=$data[$line+2];
			$hairpin{4}=$data[$line+3];
			$n=index($hairpin{4},"\\",0);#the first position of the \
			if ($n eq -1) {#only black in the structure
				$m=1;
				$n=length($hairpin{1});#to get the position of the first string
				while ($m<=4){#of each strand
					if ($hairpin{$m}=~ /^\s+\w/){
						$string=substr($&,-1,1);#the first string
					}
					if ($hairpin{$m}=~ /^\w/){#incase of first position that no blanck
						$string=substr($&,-1,1);#the first string
					}
				if (index($hairpin{$m},$string,0)<$n){#the position
					$n=index($hairpin{$m},$string,0);
				}
				$m +=1;
				}
				$n=$n-2;
			}
		else {
			while (index($hairpin{4},"\\",$n+1) ne "-1"){
				$n=index($hairpin{4},"\\",$n+1);
			}
		}
		$hairpin{1}=substr($hairpin{1},$n+2);#cut out the true hairpin
		$hairpin{2}=substr($hairpin{2},$n+2);
		$hairpin{3}=substr($hairpin{3},$n+2);
		$hairpin{4}=substr($hairpin{4},$n+2);
		#length decide
		$string=$hairpin{1}.$hairpin{2}.$hairpin{3}.$hairpin{4};
		$string=~ s/\s//g;#get rid of black
		$string=~ s/\\//g;#get rid of \
		$string=~ s/-//g;#get rid of -
		$string=~ s/\n//g;#get rid of -
		if (length($string)>=$prilength){#output the sequences
			$seq=hairpin2seq($hairpin{1},$hairpin{2},$hairpin{3},$hairpin{4});
			foreach (@sequence){
				if ($seq eq $_){
					$rp=1
				}
			}
			if ($rp eq 0){
			$hpname.="$id-mir-$serial\n";#collect the name
			open (HAIRPIN,">$path$id-mir-$serial\.fas");
			print HAIRPIN ">$id-mir-$serial","\n";
			print HAIRPIN $seq;
			close HAIRPIN;
			$sequence[$serial-1]=$seq;#add the seq to the pool for replication detecting
			$serial+=1;
			}
			$rp=0;
		}
		$line +=7;#next loop
		}
	}
	open (NAME,">$path$id\_hairpin.nm");#output the name infor
	print NAME $hpname;
	close NAME;
}
sub hairpin2seq {#conver the second structure into a line
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The hairpin2seq was used to generate a seq from second str
	#===========Usage: readlongfile(seq1,seq2,seq3,seq4)
	#===========A line seq will be resurn.
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#formathairpin2seq(seq1,seq2,seq3,seq4)
    my $s1;
    my $s2;
    my $s3;
    my $s4;
    my $seq;#for the sequence
    my $upperseq;#for the upper strand
    my $lowerseq;#for the lower strand
    ($s1,$s2,$s3,$s4)=@_;
	$s1=~ s/\n//g;
	$s2=~ s/\n//g;
	$s3=~ s/\n//g;
	$s4=~ s/\n//g;
    my $m=0;
    while ($m<=(length($s1)-1)){
		$upperseq.=substr($s1,$m,1).substr($s2,$m,1);#get the seq
		$lowerseq.=substr($s3,-($m+1),1).substr($s4,-($m+1),1);
		$m+=1;
    }
    $seq=$upperseq.$lowerseq;
    $seq=~ s/\\//;#get rid of \\
    $seq=~ s/\s//g;#get rid of black
    $seq=~ s/-//g;#get rid of -
    $seq=~ s/\n//g;#get rid of \n,if any
    return $seq;
}
sub candidate{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The candidate was used to generate the miRNA candidate of a pri-miRNA
	#===========Usage: candidate($path,$abname,$species)
	#===========*_hairpin.nm and *.fas will be used
	#===========Some primary parameter were generated and then put into <parameter>
	#			to calculate more other parameters.
	#			*_candi.nm will be output too.
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $species;
	my $path;
	my @seqname;#the name of each sequence
	my $name;#get the name of name file
	my %para;#hash for the parameters of a miRNA
	my $id="";#the id of the sequence
	my @strdata;#the data of *.out files
	my $seq_obj;#the object of sequence
	my $s;#tmp string
	my $m;#tmp number
	my $n;#tmp number
	my $seq5;#the line seq of 5' strnad
	my $seq3;#the line seq of 3' strnad
	my %pstr5;#the position of a nt in its second structure
	my %pstr3;#the position of a nt in its second structure
	my $serial=1;#the serial of each miRNA
	my $position;#the position of each nt in liner sequence
	my $candiname="";#the name of each candidate
	my $abname;
	my $range;
	($path,$abname,$species,$range)=@_;
	$name="$path$abname\_hairpin.nm";
	open (NAME,"$name");#read the name of the long sequences
	@seqname=<NAME>;
	close NAME;
	open (DATAOUT, ">$path$abname\_candidate.pmt");
	print DATAOUT "<candidate>\n";
	close DATAOUT;
   open (OUTPUT, ">$path$abname\.dat");
   print OUTPUT "";
   close OUTPUT;
	foreach (@seqname){
		$_ =~ s/\n//g;#get rid of \n
		if ($_ eq ""){
			goto line1;
		}
		$id=$_;#the the id from the name
		$id=~ s/-mir-[0-9]+//;
		open (DATA,"$path$_\.out");#read the name of the long sequences
		@strdata=<DATA>;
		close DATA;
		$para{'pristr_1'}=lc($strdata[5]);#read the second structure
		$para{'pristr_2'}=lc($strdata[6]);
		$para{'pristr_3'}=lc($strdata[7]);
		$para{'pristr_4'}=lc($strdata[8]);
		$para{'pristr_1'}=~ s/\n//g;
		$para{'pristr_2'}=~ s/\n//g;
		$para{'pristr_3'}=~ s/\n//g;
		$para{'pristr_4'}=~ s/\n//g;
		$seq_obj = Bio::SeqIO->new(-file => "$path$_\.fas");
		$para{'priseq'} = lc($seq_obj->next_seq->seq());#get the sequence
		#judge if there is any budding stem
		$s=join("",$para{'pristr_1'},$para{'pristr_2'},$para{'pristr_3'},$para{'pristr_4'});
		$s=~ s/[\s\\\.-]+//g;
		if (length($s) ne length($para{'priseq'})){
			goto line1;#budding stem
		}
		else {#no budding stem
			$para{'buddingstem'}="NO";#budding stem
			if (index ($strdata[1],"\.",0) eq -1){#incase that no"." in the value of mfe
				if ($strdata[1]=~ /-\d+/){#read the minimal free energy
					$para{'primfe'}=$&;
				}
			}
			else{
				if ($strdata[1]=~ /-\d+\.\d+/){#read the minimal free energy
					$para{'primfe'}=$&;
				}
			}
			#generate the line seq of each strand
			$s=join("",$para{'pristr_1'},$para{'pristr_2'});
			$s=~ s/[\s\\\.-]+//g;
			$seq5=substr($para{'priseq'},0,length($s));#get the sequence of 5'strand
			$seq3=substr($para{'priseq'},length($s));#get the sequence of 3'strand
			#generate the position of each nt in the second str.
			$m=0;
			$n=1;
			while ($n<=length($seq5)){#get position of each nuclitide in second structure
				if ((substr($para{'pristr_1'},$m,1) ne "-") and (substr($para{'pristr_2'},$m,1) ne "-")){
					$pstr5{$n}=$m+1;
					$n +=1;
				}
				$m +=1;
			}
			$pstr5{0}=0;
			$m=0;
			$n=1;
			while ($n<=length($seq3)){#get position of each nuclitide in second structure
				if ((substr($para{'pristr_3'},$m,1) ne "-") and (substr($para{'pristr_4'},$m,1) ne "-")){
					$pstr3{$n}=$m+1;
					$n +=1;
				}
				$m +=1;
			}
			$pstr3{0}=0;
			#generate the candidate with 20-24 in length
			#goto line;
			$position=1;
			while (length($seq5)-$position>=19){
				$m=20;
				while (($m<=24) and ($position+$m)<=length($seq5)){
					$para{'id'}="$abname-MIR-$serial\_$m";
					$candiname .=$para{'id'}."\n";
					#upper position
					$para{'upperstart'}=$pstr5{$position};#the start position of a miRNA in second str
					$para{'upperend'}=$pstr5{$position+$m-1};#the start position of a miRNA in second str
					#mi position
					$para{'mistart'}=$position;
					$para{'miend'}=$position+$m-1;
					#the second structure of the pri-miRNA
					$para{'pristr_3'}=lc($para{'pristr_3'});
					$para{'pristr_4'}=lc($para{'pristr_4'});
					$para{'pristr_1'}=lc(substr($para{'pristr_1'},0,$para{'upperstart'}-1)).uc(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_1'},$para{'upperend'}));
					$para{'pristr_2'}=lc(substr($para{'pristr_2'},0,$para{'upperstart'}-1)).uc(substr($para{'pristr_2'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_2'},$para{'upperend'}));
					#the second structure of pre-miRNA
					$para{'prestr_3'}=lc(substr($para{'pristr_3'},$para{'upperstart'}-1));
					$para{'prestr_4'}=lc(substr($para{'pristr_4'},$para{'upperstart'}-1));
					$para{'prestr_1'}=uc(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_1'},$para{'upperend'}));
					$para{'prestr_2'}=uc(substr($para{'pristr_2'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_2'},$para{'upperend'}));
					#the second structure of miRNA
					$para{'mistr_3'}=lc(substr($para{'pristr_3'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_4'}=lc(substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_1'}=uc(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_2'}=uc(substr($para{'pristr_2'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					#length
					$para{'prilenth'}=length($para{'priseq'});#prilength
					$para{'milength'}=$m;#milength
					$s=join("",$para{'prestr_1'},$para{'prestr_2'},$para{'prestr_3'},$para{'prestr_4'});
					$s=~ s/[\s\\-]+//g;
					$para{'prelength'}=length($s);
					#seq
					$para{'preseq'}=substr($para{'priseq'},$position-1,$para{'prelength'});
					$para{'miseq'}=substr($seq5,$position-1,$m);
					#strand
					$para{'strand'}='5';
					print "Calculating the miRNA candidate: $para{'id'} at $id\n";
					parameter($path,$abname,$species,$range,%para);#sent the information to calculate the parameters
					$m +=1;
				}#20-24
				$serial +=1;
				$position +=1;
			}#position
			$serial -=1;
			#line:
			$position=length($seq3);
			while ($position>=20){
				$m=20;
				while (($m<=24) and ($position >=$m)){
					$para{'id'}="$abname-MIR-$serial\_$m";
					$candiname .=$para{'id'}."\n";
					#upper position
					$para{'upperstart'}=$pstr3{$position-$m+1};#the start position of a miRNA in second str
					$para{'upperend'}=$pstr3{$position};#the start position of a miRNA in second str
					#mi position
					$para{'mistart'}=length($seq5)+length($seq3)-$position+1;
					$para{'miend'}=length($seq5)+length($seq3)-$position+1+$m-1;
					#the second structure of the pri-miRNA
					$para{'pristr_1'}=lc($para{'pristr_1'});
					$para{'pristr_2'}=lc($para{'pristr_2'});
					$para{'pristr_3'}=lc(substr($para{'pristr_3'},0,$para{'upperstart'}-1)).uc(substr($para{'pristr_3'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_3'},$para{'upperend'}));
					$para{'pristr_4'}=lc(substr($para{'pristr_4'},0,$para{'upperstart'}-1)).uc(substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_4'},$para{'upperend'}));
					#the second structure of pre-miRNA
					$para{'prestr_1'}=lc(substr($para{'pristr_1'},$para{'upperstart'}-1));
					$para{'prestr_2'}=lc(substr($para{'pristr_2'},$para{'upperstart'}-1));
					$para{'prestr_3'}=uc(substr($para{'pristr_3'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_3'},$para{'upperend'}));
					$para{'prestr_4'}=uc(substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1)).lc(substr($para{'pristr_4'},$para{'upperend'}));
					#the second structure of miRNA
					$para{'mistr_1'}=lc(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_2'}=lc(substr($para{'pristr_2'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_3'}=uc(substr($para{'pristr_3'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					$para{'mistr_4'}=uc(substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'upperend'}-$para{'upperstart'}+1));
					#length
					$para{'prilenth'}=length($para{'priseq'});#prilength
					$para{'milength'}=$m;#milength
					$s=join("",$para{'prestr_1'},$para{'prestr_2'},$para{'prestr_3'},$para{'prestr_4'});
					$s=~ s/[\s\\-]+//g;
					$para{'prelength'}=length($s);
					#seq
					$para{'preseq'}=substr($para{'priseq'},$m-$position-$para{'prelength'},$para{'prelength'});
					$para{'miseq'}=substr($seq3,-$position,$m);
					#strand
					$para{'strand'}='3';
					print "Calculating the miRNA candidate: $para{'id'} at $id\n";
					parameter($path,$abname,$species,$range,%para);#sent the information to calculate the parameters
					$m +=1;
				}
				$serial +=1;
				$position-=1;
			}
		}#no budding stem
		line1:
	}#each seq
	if ($id eq ""){
	  print "All Done!\nNo miRNA candidates were found!\n";
	  exit;
	}
	open (OUTPUT,">$path$id\_candi.nm");
    print OUTPUT $candiname;
    close OUTPUT;
	open (DATAOUT, ">>$path$abname\_candidate.pmt");
	print DATAOUT "<\/candidate>\n";
	close DATAOUT;
}#sub
sub parameter{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The parameter was used to generate the miRNA parameter values
	#===========Usage: parameter($path,$abname,$species,%para)
	#===========Some other sub programs will be called:
	#			-gc
	#			-pairs
	#			-gu
	#			-ntcontent
	#			-internalloop
	#			-internalloopnumber
	#			-unpairedbases
	#			-unpairedrate
	#===========The *.pmt file will be created.
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $path;
	my $species;
	my %para;#a hash for all parameters
	my @strdata;#the data of *.out file
	my $s;#tmp string
	my $s1;#tmp string
	my $s2;#tmp string
	my $m;#tmp number
	my $n;#tmp number
	my @arr;#xml files
	my $xmlobj;#sml object
	my $xmldata;#xml data
	my $xmlfile;#xmal data
	my $abname;
	my $range;
	($path,$abname,$species,$range,%para)=@_;#receive the parameter
	#length
	$para{'prilength'}=length($para{'priseq'});
	$para{'prelength'}=length($para{'preseq'});
	$para{'milength'}=length($para{'miseq'});
	#premfe
	open (OUTPUT,">".$path."tmp.fas");#output the pre seq
	print OUTPUT ">tmp\n";
	print OUTPUT $para{'preseq'};
	close OUTPUT;
	callunafd($path,$abname,'-pre');#call unafold to generate the mfe
	open (DATA,$path."tmp.out");
	@strdata=<DATA>;
	close DATA;
	unlink $path."tmp.out";
	if (index ($strdata[1],"\.",0) eq -1){#incase that no"." in the value of mfe
		if ($strdata[1]=~ /-\d+/){#read the minimal free energy
			$para{'premfe'}=$&;
		}
	}
	else{
		if ($strdata[1]=~ /-\d+\.\d+/){#read the minimal free energy
			$para{'premfe'}=$&;
		}
	}
	#gc
	$para{'prigc'}=gc($para{'priseq'});#prigc
	$para{'pregc'}=gc($para{'preseq'});#pregc
	$para{'migc'}=gc($para{'miseq'});#migc
	#mfei
	#$para{'primfei'}=sprintf '%.2f',($para{'primfe'}*100)/($para{'prilength'}*$para{'prigc'});
	#$para{'premfei'}=sprintf '%.2f',($para{'premfe'}*100)/($para{'prelength'}*$para{'pregc'});
	#pairs
	$para{'pripairs'}=pairs($para{'pristr_2'},'yes');
	$para{'prepairs'}=pairs($para{'prestr_2'},'yes');
	$para{'mipairs'}=pairs($para{'mistr_2'});
	#gu
	$para{'prigu'}=gu($para{'pristr_2'},$para{'pristr_3'},'yes');
	$para{'pregu'}=gu($para{'prestr_2'},$para{'prestr_3'},'yes');
	$para{'migu'}=gu($para{'mistr_2'},$para{'mistr_3'});
	#ntcontent
	$para{'printcontent_a'}=ntcontent($para{'priseq'},'a');
	$para{'printcontent_u'}=ntcontent($para{'priseq'},'u');
	$para{'printcontent_c'}=ntcontent($para{'priseq'},'c');
	$para{'printcontent_g'}=ntcontent($para{'priseq'},'g');
	$para{'prentcontent_a'}=ntcontent($para{'preseq'},'a');
	$para{'prentcontent_u'}=ntcontent($para{'preseq'},'u');
	$para{'prentcontent_c'}=ntcontent($para{'preseq'},'c');
	$para{'prentcontent_g'}=ntcontent($para{'preseq'},'g');
	$para{'mintcontent_a'}=ntcontent($para{'miseq'},'a');
	$para{'mintcontent_u'}=ntcontent($para{'miseq'},'u');
	$para{'mintcontent_c'}=ntcontent($para{'miseq'},'c');
	$para{'mintcontent_g'}=ntcontent($para{'miseq'},'g');
	#firstbase
	$para{'firstbase'}=uc(substr($para{'miseq'},0,1));
	#BasalSegment
	$s1=$para{'pristr_1'};
	$s1=~ s/[-|\\\^]+//g;#get rid of unnecessary charaters
	$s2=$para{'pristr_4'};
	$s2=~ s/[-|\\\^]+//g;#get rid of unnecessary charaters
	my $basalen1=0;
	my $basalen2=0;
	$basalen1=index($s1," ",0);
	$basalen2=index($s2," ",0);
	if ($basalen1>=$basalen2) {
		$para{'length_basalsegment'}=$basalen1;
		$para{'basalend'}=$basalen1;#the end position of basal segment
	}
	else {
		$para{'length_basalsegment'}=$basalen2;
		$para{'basalend'}=$basalen2;
	}
		#if the mature miRNA is locate in the reagin
	if (($para{'length_basalsegment'}+length($para{'prestr_1'}))>length($para{'pristr_1'})){
		$para{'length_basalsegment'}=0;
	}
	#terminal loop
	$s1=$para{'pristr_1'};
	chop($s1);#get rid of the black in the terminal
	my $terminalloopstem=0;
	until (substr($s1,-1,1) eq " "){#get the length of terminalloopstem
		chop($s1);
		$terminalloopstem++;
	}
	$para{'loopstart'}=length($para{'pristr_1'})-$terminalloopstem;#the start position of the loop
	if (index($para{'pristr_2'},"\\") eq -1) {#no \
		$para{'length_terminalloop'}=2*$terminalloopstem+2;
	}
	else {
		$para{'length_terminalloop'}=2*$terminalloopstem+1;
	}
	#lowerstem
	$para{'length_lowerstem'}=$para{'upperstart'}-$para{'basalend'}-1;
	if ($para{'length_lowerstem'}<=0){
		$para{'length_lowerstem'}="NONE";
	}
	#upperstem
	$para{'length_upperstem'}=$para{'upperend'}-$para{'upperstart'}+1;
	#topstem
	$para{'length_topstem'}=$para{'loopstart'}-$para{'upperend'}-1;
	if ($para{'length_topstem'}<=0){
		$para{'length_topstem'}="NONE";
	}
	#internalloop
	$para{'priinternalloop'}=internalloop(substr($para{'pristr_1'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1),
										substr($para{'pristr_4'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1));
	$para{'preinternalloop'}=internalloop(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}),
										substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}));
	$para{'miinternalloop'}=internalloop($para{'mistr_1'},$para{'mistr_4'});
	if ($para{'length_lowerstem'} ne "NONE"){
		$para{'internalloop_lowerstem'}=internalloop(substr($para{'pristr_1'},$para{'basalend'},$para{'length_lowerstem'}),
													 substr($para{'pristr_4'},$para{'basalend'},$para{'length_lowerstem'}));
	}
	else{
		$para{'internalloop_lowerstem'}="NONE"
	}
	if ($para{'length_topstem'} ne "NONE"){
		$para{'internalloop_topstem'}=internalloop(substr($para{'pristr_1'},$para{'upperend'},$para{'length_topstem'}),
													 substr($para{'pristr_4'},$para{'upperend'},$para{'length_topstem'}));
	}
	else{
		$para{'internalloop_topstem'}="NONE"
	}
	#internalloop number
	$para{'priinternalloopnumber'}=internalloopnumber(substr($para{'pristr_1'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1),
										substr($para{'pristr_4'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1));
	$para{'preinternalloopnumber'}=internalloopnumber(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}),
										substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}));
	$para{'miinternalloopnumber'}=internalloopnumber($para{'mistr_1'},$para{'mistr_4'});
	if ($para{'length_lowerstem'} ne "NONE"){
		$para{'internalloopnumber_lowerstem'}=internalloopnumber(substr($para{'pristr_1'},$para{'basalend'},$para{'length_lowerstem'}),
													 substr($para{'pristr_4'},$para{'basalend'},$para{'length_lowerstem'}));
	}
	else{
		$para{'internalloopnumber_lowerstem'}="NONE"
	}
	if ($para{'length_topstem'} ne "NONE"){
		$para{'internalloopnumber_topstem'}=internalloopnumber(substr($para{'pristr_1'},$para{'upperend'},$para{'length_topstem'}),
													 substr($para{'pristr_4'},$para{'upperend'},$para{'length_topstem'}));
	}
	else{
		$para{'internalloopnumber_topstem'}="NONE"
	}
	#unpairedbases
	$para{'priunpairedbases'}=unpairedbases(substr($para{'pristr_1'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1),
											substr($para{'pristr_4'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1));
	$para{'preunpairedbases'}=unpairedbases(substr($para{'pristr_1'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}),
											substr($para{'pristr_4'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}));
	$para{'miunpairedbases'}=unpairedbases($para{'mistr_1'},$para{'mistr_4'});
	if ($para{'length_lowerstem'} ne "NONE"){
		$para{'unpairedbases_lowerstem'}=unpairedbases(substr($para{'pristr_1'},$para{'basalend'},$para{'length_lowerstem'}),
													 substr($para{'pristr_4'},$para{'basalend'},$para{'length_lowerstem'}));
	}
	else{
		$para{'unpairedbases_lowerstem'}="NONE"
	}
	if ($para{'length_topstem'} ne "NONE"){
		$para{'unpairedbases_topstem'}=unpairedbases(substr($para{'pristr_1'},$para{'upperend'},$para{'length_topstem'}),
													 substr($para{'pristr_4'},$para{'upperend'},$para{'length_topstem'}));
	}
	else{
		$para{'unpairedbases_topstem'}="NONE"
	}
	#unpairedrate
	$para{'priunpairedrate'}=unpairedrate($para{'priunpairedbases'},
											substr($para{'pristr_2'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1),
											substr($para{'pristr_3'},$para{'basalend'},$para{'loopstart'}-$para{'basalend'}-1));
	$para{'preunpairedrate'}=unpairedrate($para{'preunpairedbases'},
											substr($para{'pristr_2'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}),
											substr($para{'pristr_3'},$para{'upperstart'}-1,$para{'loopstart'}-$para{'upperstart'}));
	$para{'miunpairedrate'}=unpairedrate($para{'miunpairedbases'},$para{'mistr_2'},$para{'mistr_3'});
	if ($para{'length_lowerstem'} ne "NONE"){
		$para{'unpairedrate_lowerstem'}=unpairedrate($para{'unpairedbases_lowerstem'},
													  substr($para{'pristr_2'},$para{'basalend'},$para{'length_lowerstem'}),
													 substr($para{'pristr_3'},$para{'basalend'},$para{'length_lowerstem'}));
	}
	else{
		$para{'unpairedrate_lowerstem'}="NONE"
	}
	if ($para{'length_topstem'} ne "NONE"){
		$para{'unpairedrate_topstem'}=unpairedrate($para{'unpairedbases_topstem'},
													substr($para{'pristr_2'},$para{'upperend'},$para{'length_topstem'}),
													 substr($para{'pristr_3'},$para{'upperend'},$para{'length_topstem'}));
	}
	else{
		$para{'unpairedrate_topstem'}="NONE"
	}
	#stability
	$s1=lc(join("",substr($para{'mistr_2'},0,4),substr($para{'mistr_3'},0,4)));
	$s2=lc(join("",substr($para{'mistr_2'},-4,4),substr($para{'mistr_3'},-4,4)));
	$s1=~ s/\s+//g;
	$s1=~ s/c/zz/g;
	$s2=~ s/\s+//g;
	$s2=~ s/c/zz/g;
	if ($para{'strand'} eq "5"){
		if (length($s2) ne 0){
			$para{'stability'}=sprintf '%.2f',length($s1)/length($s2);
		}
		else{
			$para{'stability'}=-1;
		}
	}
	else{
		if (length($s1) ne 0){
			$para{'stability'}=sprintf '%.2f',length($s2)/length($s1);
		}
		else{
			$para{'stability'}=-1;
		}
	}
	#overhang
	$s="";
	$m=1;
	while ((length($s) < 2)  and ($para{'upperend'}+$m)<=length($para{'pristr_3'})){
		if ($para{'strand'} eq "5"){#generate the two nt
			$s=join("",substr($para{'pristr_3'},$para{'upperend'},$m),substr($para{'pristr_4'},$para{'upperend'},$m));
		}
		else{
			$s=join("",substr($para{'pristr_1'},$para{'upperstart'}-$m-1,$m),substr($para{'pristr_2'},$para{'upperstart'}-$m-1,$m));
		}
		$s=~ s/[\s\\-]+//g;
		$m++;
	}
	if ($s eq ""){#no overhang
		$para{'penultimateposition'}="NONE";
		$para{'terminalnucleotide'}="NONE";
	}
	if (length($s) eq 1){#one overhang
		$para{'penultimateposition'}=$s;
		$para{'terminalnucleotide'}="NONE";
	}
	if (length($s) eq 2){#two overhang
		if ($para{'strand'} eq "5"){
			$para{'penultimateposition'}=substr($s,0,1);
			$para{'terminalnucleotide'}=substr($s,1,1);
		}
		else{
			$para{'penultimateposition'}=substr($s,1,1);
			$para{'terminalnucleotide'}=substr($s,0,1);
		}
	}
	$para{'penultimateposition'}=uc($para{'penultimateposition'});
	$para{'terminalnucleotide'}=uc($para{'terminalnucleotide'});
	pmt2svmdat($path,$abname,$range,%para);
	#output
	@arr = {%para};
    $xmlobj = new XML::Simple (NoAttr=>1, RootName=>"$para{'id'}");#create object
    $xmldata = $xmlobj->XMLout(@arr);
	$xmlfile=Dumper($xmldata);
	$xmlfile= substr($xmlfile,9,length($xmlfile)-12);
	$xmlfile=~ s/\\+/\\/;
	open (DATAOUT, ">>$path$abname\_candidate.pmt");
	print DATAOUT "$xmlfile\n";
	close DATAOUT;
}
sub gc{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The gc was used to generate gc content of given seq
	#===========Usage: gc($seq)
	#===========The GC content will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq;#receive the sequences
	my $s;#tmp string
	my $gc;
	($seq)=@_;
	$s=$seq;
	$s=~ s/[aut]+//g;
	$gc=sprintf '%4.4f', length($s)/length($seq);#prigc
	return $gc;
}
sub pairs{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The pairs was used to generate the number of pairs of second str
	#===========Usage: pairs($seq,$loop)
	#			$loop is to test whether there is any nt in the loop
	#			yes/no to decide the $loop value
	#===========The number of pair bands will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq;
	my $loop;
	my $pairs;
	($seq,$loop)=@_;
	if (lc($loop) eq "yes"){
		chop($seq);
	}
	$seq=~ s/\s//g;
	$pairs=length($seq);
	return $pairs;
}
sub gu{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The gu was used to generate the number of GU wobbles
	#===========Usage: gu(seq1,seq2,yes/no)
	#			$loop is to test whether there is any nt in the loop
	#			yes/no to decide the $loop value
	#===========The number of GU wobbles will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq1;
	my $seq2;
	my $s;#tmp string
	my $loop;
	my $gu;
	my $u;
	my $a;
	($seq1,$seq2,$loop)=@_;
	if (lc($loop) eq "yes"){
		chop($seq1);
		chop($seq2);
	}
	$s=join("",$seq1,$seq2);
	$s=~ s/\s+//g;
	$u=lc($s);
	$u=~ s/[ut]+//g;
	$a=lc($s);
	$a=~ s/[a]+//g;
	$gu=length($a)-length($u);
	return $gu;
}
sub ntcontent{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The ntcontent was used to generate the nt content of four nts
	#===========Usage: ntcontent($seq,$nt)
	#			$nt reprecent A,U,G OR C
	#===========The nt content of given nt will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq;
	my $s;
	my $nt;
	my $ntcontent;
	($seq,$nt)=@_;
	if (lc($nt) eq "a"){
		$s=$seq;
		$s=~ s/[a]+//g;
		$ntcontent=sprintf '%4.4f', (length($seq)-length($s))/length($seq);
	}
	if ((lc($nt) eq "t") or (lc($nt) eq "u")){
		$s=$seq;
		$s=~ s/[tu]+//g;
		$ntcontent=sprintf '%4.4f', (length($seq)-length($s))/length($seq);
	}
	if (lc($nt) eq "c"){
		$s=$seq;
		$s=~ s/[c]+//g;
		$ntcontent=sprintf '%4.4f', (length($seq)-length($s))/length($seq);
	}
	if (lc($nt) eq "g"){
		$s=$seq;
		$s=~ s/[g]+//g;
		$ntcontent=sprintf '%4.4f', (length($seq)-length($s))/length($seq);
	}
	return $ntcontent;
}
sub internalloop{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The internalloop was used to generate the size of the biggest internal loop
	#===========Usage: internalloop($seq1,$seq2)
	#===========The size of the biggest internal loop will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#format internalloop(seq1,seq2)
	my $seq1;
	my $seq2;
	($seq1,$seq2)=@_;
	$seq1=~ s/[-]+//g;
	$seq1=~ s/\s+/>/g;
	$seq2=~ s/[-]+//g;
	$seq2=~ s/\s+/>/g;
	if (substr($seq1,-1,1) eq ">"){#get rid of the final > which might black splict.
		chop($seq1);
	}
	if (substr($seq2,-1,1) eq ">"){
		chop($seq2);
	}
	my @internalloop=split(">",join(">",$seq1,$seq2));
	my $lengthinternalloop=0;
	foreach (@internalloop) {
		if (length($_)>$lengthinternalloop) {
			$lengthinternalloop=length($_)
		}
	}
	return $lengthinternalloop;
}
sub internalloopnumber{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The internalloopnumber was used to generate the number of internal loop
	#===========Usage: internalloopnumber($seq1,$seq2)
	#===========The number of internal loop will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq1;
	my $seq2;
	($seq1,$seq2)=@_;
	$seq1=~ s/[-]+//g;
	$seq1=~ s/\s+/>/g;
	$seq1=~ s/^>//;
	$seq1=~ s/>$//;
	$seq2=~ s/[-]+//g;
	$seq2=~ s/\s+/>/g;
	$seq2=~ s/^>//;
	$seq2=~ s/>$//;
	my @internalloop=split(">",join(">",$seq1,$seq2));
	my $lengthinternalloopnumber=@internalloop;
	return $lengthinternalloopnumber;
}
sub unpairedbases{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The unpairedbases was used to generate the size of unpaired bases
	#===========Usage: unpairedbases($seq1,$seq2)
	#===========The size of unpaired bases will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $seq1;
	my $seq2;
	my $s;
	($seq1,$seq2)=@_;
	$s=join("",$seq1,$seq2);
	$s=~ s/[\s-]+//g;
	return length($s);
}
sub unpairedrate{#parameter
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The unpairedrate was used to generate the unpaired rate of seq
	#===========Usage: unpairedrate(unpairedbases, seq1,seq2)
	#===========The unpaired rate of seq will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $unpairedbases;
	my $seq1;
	my $seq2;
	my $s;
	my $rate;
	($unpairedbases,$seq1,$seq2)=@_;
	$s=join("",$seq1,$seq2);
	$s=~ s/\s+//g;
	if (($unpairedbases+length($s)) ne 0) {
		$rate=sprintf '%4.4f',($unpairedbases)/($unpairedbases+length($s));
	}
	else{
		$rate=sprintf '%4.4f',1;
	}
	return $rate;
}
sub predict{#to predict the data
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The predict was used to predict the data with svm
	#===========Usage: predict($path,$abname,$species)
	#===========The collect seq will be put in *._mir.nm
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#the species and parameter should be used
	my $path;
	my $species;
	my $svmresult;#predict result for one parameter
	my $svm;#svm project
	my $svmdata;
	my @data;
	my @row;
	my $label;
	my $testdata;#test data
	my $abname;
	my $testname;
	my $level;
	print "Predicting...";
	($path,$abname,$species,$level)=@_;
	open(IF, "$path$abname\.dat");
	@data=<IF>;
	close IF;
	open (OT,">$path$abname\_mir\.nm");
	print OT "";
	close OT;
	$svm = new Algorithm::SVM(Model => "./models/$species\_$level.model");
	foreach (@data){
		$_ =~ s/\n//g;
		if ($_ ne ""){
			$_=~ s/\s/,/g;
			@row=split (",",$_);
			$label=substr($row[0],0,1);
			$testname=substr($row[0],2);
			splice(@row,0,1);
			$svmdata=[];
			foreach (@row){
			   $_=~s/\n//g;
				if ($_ ne ""){
					push(@$svmdata,$_);
				}
			}
			$testdata = new Algorithm::SVM::DataSet(Label => $label,Data=>$svmdata);
			$svmresult= $svm->predict($testdata);#predict
			if ($svmresult eq "1"){
				open (OUTPUT,">>$path$abname\_mir.nm");
				print OUTPUT "$testname\n";
				close OUTPUT;
			}
			print '.';
		}
	}
	print "\n";
}
sub nt2number{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The nt2number was used to translate the nt to ACC number
	#===========Usage: nt2number(nt)
	#===========The number of acc will be return
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $value;
	($value)=@_;
	$value=lc($value);
	if ($value eq "none"){
		$value="-1";
	}
	elsif ($value eq ""){
		$value=0;#if nothing
	}
	elsif ($value eq "a"){
		$value="1,0,0,0";
	}
	elsif ($value eq "c"){
		$value="0,1,0,0";
	}
	elsif ($value eq "g"){
		$value="0,0,1,0";
	}
	elsif (($value eq "u") or ($value eq "t")){
		$value="0,0,0,1";
	}
	elsif ($value eq "n"){
		$value="0,0,0,0";
	}
	return $value;
}
sub out{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The out was used to generate the result
	#===========Usage: out($path,$abname)
	#===========The *_mir1.out and *_mir2.out will be created
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $path;
	my $abname;
	my $xml;
	my @mir;
	my $mirna;
	my $data1;
	my $data2;
	my $head1;#for the sequence head
	my $head;
	my %para;
	my $id;
	#my $priseq;
	my $miseq;
	my @parameter;
	my @number;
	my %mirbase;
	my $blast;
	my @keys;
	my $level;
	($path,$abname,$level,%mirbase)=@_;
	@number=summary($path,$abname);
	open (IN,"$path$abname\_mir.nm");
	@mir=<IN>;
	close IN;
	$head="miRNA predicting result by miRPara1.0\n";
	$head .="By Yonggan Wu and Simon Rayner\n";
	$head .='Report bugs to raynere@wh.iov.cn or weasteam@gmail.com'."\n";
	$head .="Wuhan Institute of Virology, Chinese Academic of Science.\n";
	$head .="Wuhan, 430071, China\n\n";
	$head1="--------------------------------------------------------------------------------------\n";
	$head1.="Your data was predicted at level: $level\n";
	$head1.="The number of pri-miRNAs, miRNA areas and miRNA candidates are:\n";
	$head1.="pri-miRNA           $number[0]\n";
	$head1.="miRNA area          $number[2]\n";
	$head1.="miRNA candidates    $number[1]\n";
	$head1.="--------------------------------------------------------------------------------------\n";
	$head1.="Name                miRNA sequences               blast in miRBase12.0\n";
	$head1.="--------------------------------------------------------------------------------------\n";
   @parameter=pmt('all');
	if ($number[1] eq 0){#if no positive result
	   $data1 .="No miRNA avaiable in your sequence.";
	   $data2 .="No miRNA avaiable in your sequence.";
	}
	else{
		$xml = XMLin("$path$abname\_candidate.pmt");#read the xml file
		@keys=keys(%mirbase);
		foreach (@mir){
			$_=~ s/\n//;
			if ($_ ne ""){
				$mirna=$_;
				foreach (@parameter){
					$para{$_}=$xml->{$mirna}->{$_};
				}
				$id=$para{'id'}.(" " x (20-length($para{'id'})));
				#$priseq=lc(substr($para{'priseq'},0,$para{'mistart'}-1)).uc(substr($para{'priseq'},$para{'mistart'}-1,$para{'milength'})).lc(substr($para{'priseq'},$para{'miend'}));
				$miseq=uc($para{'miseq'}).(" " x (30-length($para{'miseq'})));
				$blast="";
				foreach (@keys){
					 if ($_ eq lc($para{'miseq'})){
						$blast=$mirbase{lc($para{'miseq'})};
					 }
				}
				$data1 .="$id$miseq$blast\n";
				$data2 .=display(%para)."-------------------------->END<--------------------------\n\n";
			}
		}
	}
	open (OT,">$path$abname\_mir1\.out");
	print OT $head;
	print OT $head1;
	print OT $data1;
	close OT;
	open (OT,">$path$abname\_mir2\.out");
	print OT $head;
	print OT $data2;
	close OT;
}
sub display{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The display was used to display the data files
	#===========Usage: display(%para)
	#===========The data will be returned
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my %para;
	my $data;
	my @p;
	(%para)=@_;
	@p=pmt('display');
	$data="==================>$para{'id'}<==================\n";
	foreach (@p){
		$data.=uc($_).":".(" " x (30-length($_))).$para{$_}."\n";
	}
	return $data;
}
sub pmt2svmdat{
   #>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
   #===========The pmt2svmdat.pl was used to generate the pmt data to svm data
   #===========Usage: perl pmt2xls.pl *.pmt
   #			Note: only *.pmt files were avaiable
   #===========The data were pre-filtered with range99
   #===========A each parameter value will be put in a *.dat
   #>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
   my @svmparameter;#svm parameter data
   my @rangeparameter;#range parameter data
   my $dat;#positive svm data
   my $value;#each single value
   my $path;
   my $abname;
   my $rangeresult;
   my $range;#xml range data;
   my %para;
   #print "Converting to SVM data";
   ($path,$abname,$range,%para)=@_;
	@svmparameter=pmt('svm');
	@rangeparameter=pmt('range');
	$rangeresult=0;
	foreach (@rangeparameter){
		$rangeresult +=compare($para{$_},$range->{$_}->{'lower'},$range->{$_}->{'upper'});
	}
	if (($rangeresult eq 61) and (uc($para{'buddingstem'}) eq "NO")){
		$value=$para{"id"};
		$dat="2_$value ";#clear the data
		foreach (@svmparameter){
			$value=$para{$_};
			if (($_ eq "penultimateposition") or ($_ eq "terminalnucleotide")){#incase of the uncorrect value
				if (uc($value) eq "NONE"){
					$value="N";
				}
			}
			$value=nt2number($value);
			$dat .="$value,";
		}
		$dat=~ s/,$//;
		open (OUTPUT, ">>$path$abname\.dat");
		print OUTPUT "$dat\n";
		close OUTPUT;
	}
}
sub compare{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The compare was used to decide whether a value in in certain range
	#===========Usage: compare(n1,n2,n3,)
	#===========the value 1 for true or 0 for flase will be return
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $n1="";
	my $n2="";
	my $n3="";
	my $result;
	($n1,$n2,$n3)=@_;
	if ($n1 eq "NONE"){
		$n1="-";
	}
	if ($n2 eq "-"){
		$n2="";
	}
	if ($n3 eq "-"){
		$n3="";
	}
	if ($n2 ne ""){
		if (($n3 ne "") and ($n1 ne "-")){
			if (($n1 >=$n2) and ($n1<=$n3)){
			$result=1;
			}
			else{
				$result=0;
			}
		}
		else{
			if ($n1 ne "-"){
				if ($n1 >=$n2){
					$result=1;
				}
				else{
					$result=0;
				}
			}
			else{
				$result=1;
			}
		}
	}
	else{
		if (($n3 ne "")and ($n1 ne "-")){
			if (($n1<=$n3) and ($n1 ne "-")){
				$result=1;
			}
			else{
				$result=0;
			}
		}
		else{
			$result=1;
		}
	}
	return $result;
}
sub pmt{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The pmt was used to provide pmt files
	#===========Usage: pmt(parameter)
	#			--all all parameters
	#			--range the range parameters
	#			--svm the svm parameters
	#			--display the display parameters
	#===========the parameters will be return
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $class;
	my @parameter;
	($class)=@_;
	if (lc($class) eq "all"){
		@parameter=("id","basalend","firstbase","internalloop_lowerstem",
					"internalloop_topstem","internalloopnumber_lowerstem",
					"internalloopnumber_topstem","length_basalsegment",
					"length_lowerstem","length_terminalloop","length_topstem",
					"length_upperstem","loopstart","miacc","miend","migc","migu",
					"miinternalloop","miinternalloopnumber","milength","mintcontent_a",
					"mintcontent_c","mintcontent_g","mintcontent_u","mipairs","miseq",
					"mistart","mistr_1","mistr_2","mistr_3","mistr_4","miunpairedbases",
					"miunpairedrate","penultimateposition","pregc","pregu",
					"preinternalloop","preinternalloopnumber","prelength","premfe",
					"premfei","prentcontent_a","prentcontent_c","prentcontent_g",
					"prentcontent_u","prepairs","preseq","prestr_1","prestr_2",
					"prestr_3","prestr_4","preunpairedbases","preunpairedrate",
					"prigc","prigu","priinternalloop","priinternalloopnumber",
					"prilength","primfe","primfei","printcontent_a","printcontent_c",
					"printcontent_g","printcontent_u","pripairs","priseq","pristr_1",
					"pristr_2","pristr_3","pristr_4","priunpairedbases","priunpairedrate",
					"stability","strand","terminalnucleotide","unpairedbases_lowerstem",
					"unpairedbases_topstem","unpairedrate_lowerstem","unpairedrate_topstem",
					"upperend","upperstart");#81
	}
	elsif (lc($class) eq "range"){
		@parameter=("basalend","firstbase","internalloop_lowerstem","internalloop_topstem",
				"internalloopnumber_lowerstem","internalloopnumber_topstem",
				"length_basalsegment","length_lowerstem","length_terminalloop",
				"length_topstem","length_upperstem","loopstart","miend","migc","migu",
				"miinternalloop","miinternalloopnumber","milength","mintcontent_a",
				"mintcontent_c","mintcontent_g","mintcontent_u","mipairs","mistart",
				"miunpairedbases","miunpairedrate","penultimateposition","pregc",
				"pregu","preinternalloop","preinternalloopnumber","prelength","premfe",
				"prentcontent_a","prentcontent_c","prentcontent_g",
				"prentcontent_u","prepairs","preunpairedbases","preunpairedrate",
				"prigc","prigu","priinternalloop","priinternalloopnumber","prilength",
				"primfe","printcontent_a","printcontent_c","printcontent_g",
				"printcontent_u","pripairs","priunpairedbases","priunpairedrate",
				"stability","terminalnucleotide","unpairedbases_lowerstem",
				"unpairedbases_topstem","unpairedrate_lowerstem","unpairedrate_topstem",
				"upperend","upperstart");#61
	}
	elsif (lc($class) eq "svm"){
		@parameter=("firstbase","prepairs","prelength","mipairs","mistart",
					"miinternalloop","terminalnucleotide","prigc");#22
#		@parameter=("firstbase","internalloop_lowerstem","internalloop_topstem",
#					"length_basalsegment","loopstart","miend","migu",
#					"miinternalloop","miinternalloopnumber","mintcontent_a",
#					"mintcontent_c","mintcontent_g","mistart","miunpairedbases",
#					"miunpairedrate","penultimateposition","pregu","preunpairedrate",
#					"stability","terminalnucleotide","unpairedrate_lowerstem",
#					"unpairedrate_topstem");#22
	}
	elsif (lc($class) eq "display"){
		@parameter=("id","mistart","miend",
		"miseq","mistr_1","mistr_2","mistr_3","mistr_4",
		"preseq","prestr_1","prestr_2","prestr_3","prestr_4",
		"priseq","pristr_1","pristr_2","pristr_3","pristr_4",
		"milength","prelength","prilength",
		"length_basalsegment","length_lowerstem","length_upperstem","length_topstem","length_terminalloop",
		"mipairs","prepairs","pripairs",
		"premfe","primfe",
		"migc","pregc","prigc",
		"mintcontent_a","mintcontent_c","mintcontent_g","mintcontent_u",
		"prentcontent_a","prentcontent_c","prentcontent_g","prentcontent_u",
		"printcontent_a","printcontent_c","printcontent_g","printcontent_u",
		"miinternalloop","preinternalloop","priinternalloop",
		"internalloop_lowerstem","internalloop_topstem",
		"miinternalloopnumber","preinternalloopnumber","priinternalloopnumber",
		"internalloopnumber_lowerstem","internalloopnumber_topstem",
		"miunpairedbases","preunpairedbases","priunpairedbases",
		"unpairedbases_lowerstem","unpairedbases_topstem",
		"miunpairedrate","preunpairedrate","priunpairedrate",
		"unpairedrate_lowerstem","unpairedrate_topstem",
		"migu","pregu","prigu",
		"strand","firstbase","penultimateposition","terminalnucleotide",
		"mistart","miend","stability");#81
	}
	else{
		@parameter=();
	}
	return @parameter;
}
sub summary{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The summary was used to analysis the number of pri and mi RNAs
	#===========Usage: summary($path,$abname)
	#===========the number of pri and miRNA will be return.
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $abname;
	my $path;
	my @number;
	my @data;
	my $m;#tmp number
	my $previous="";#previous candidate
	($path,$abname)=@_;
	open (IN,"$path$abname\_hairpin.nm");
	@data=<IN>;
	close IN;
	$number[0] =@data;#number of pri-miRNA
	@data=();
	open (IN,"$path$abname\_mir.nm");
	@data=<IN>;
	close IN;
	$number[1]=@data;#number of miRNA candidate
	$m=0;
	$number[2]=0;
	foreach (@data){
	  $_=~ s/\n//g;
	  if ($_ ne ""){
		 if ((lc(substr($_,0,3)) eq lc(substr($previous,0,3))) or ($previous eq "")){
			if (($m eq "0") or (($m ne "0") and ((substr($_,index($_,'-MIR-')+5,index($_,'_')-index($_,'-MIR-')-5)-$m)>1))){
			   $number[2]+=1;
			}
			$m=substr($_,index($_,'-MIR-')+5,index($_,'_')-index($_,'-MIR-')-5);
		 }
		 else{
			$number[2]+=1;
		 }
		 $previous=$_;
	  }
	}
	return @number;
}
sub path{
	#>>>>>>>>>>>>>>>>>>>>>>>>>>INTRODUCTION<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	#===========The path was used to get the path of the given file
	#===========Usage: path($path)
	#===========the path will be return.
	#>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>END<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	my $m;
	my $inputfile;
	($inputfile)=@_;
	if (index($inputfile,"\/") ne -1){#get the parth
		$m=0;
		while (index($inputfile,"\/",$m+1) ne "-1"){
			$m=index($inputfile,"\/",$m+1);
		}
		$path=substr($inputfile,0,$m+1);
	}
	else{
		$path="";
	}
	return $path;
}
