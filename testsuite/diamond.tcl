#!/bin/sh
# tricking... the line after a these comments are interpreted as standard shell script \
    PLATFORM=`uname -s`; if [ "$1" != "" ]; then NP=$1; else NP=2; fi
# OSF1 \
    if test $PLATFORM = OSF1; then  exec dmpirun -np $NP $ESPRESSO_SOURCE/$PLATFORM/Espresso $0 $*
# AIX \
    elif test $PLATFORM = AIX; then exec poe $ESPRESSO_SOURCE/$PLATFORM/Espresso $0 $* -procs $NP
# Linux \
    else export EF_ALLOW_MALLOC_0=1; exec mpirun -np $NP -nsigs $ESPRESSO_SOURCE/$PLATFORM/Espresso $0 $*;
# \
    fi;

#############################################################
#                                                           #
#  Test System 6: Diamond Hydrogel Networks                 #
#                                                           #
#                                                           #
#  Created:       08.04.2003 by BAM                         #
#                                                           #
#############################################################

puts " "
puts "==================================================="
puts "=                  diamond.tcl                    ="
puts "==================================================="
puts " "

puts "Program Information: \n[code_info]\n"



#############################################################
#  Parameters                                               #
#############################################################

# System identification: 
set name  "diamond"
set ident "_t6"

# On 'yes' connects to 'vmd' visualizing current configuration
set vmd_output "yes"


# System parameters
#############################################################

set N_node  8
set N_P     16 
set MPC     20
set N_CI    328
set N_T     [expr $N_node + $N_P*$MPC + $N_CI]
set packing { 0.0005 0.00075 0.001 0.0025 0.005 0.0075 0.01 0.025 0.05 0.1 }


# Interaction parameters
#############################################################

# repulsive Lennard Jones
set lj1_eps     1.0
set lj1_sig     1.0
set lj1_cut     1.122462048309373
set lj1_shift   [expr -4.0*$lj1_eps*(pow($lj1_cut,-12)-pow($lj1_cut,-6))]
# set lj1_cforce  [expr 48*$lj1_epsilon*(0.5*pow($lj1_cut,-7)-pow($lj1_cut,-13))]

# attractive FENE
set fene_k      15.551
set fene_r      1.25

# electrostatics
set bjerrum     1.75241
set accuracy    1.0e-4



# Integration parameters
#############################################################

setmd time_step 0.012
setmd skin      0.4
setmd gamma     1.0
setmd temp      1.0

# warmup integration (with capped LJ potential) until particles are at least $min_dist apart (but at least $min_loop loops)
set warm_step   200
set warm_loop   300
set warm_cap1   10
set warm_incr   25
set min_dist    0.9
set min_loop    200

# integration (with full LJ potential) for $int_time
set int_step    1000
set int_time    [expr 1000000*[setmd time_step]]


# Other parameters
#############################################################

set tcl_precision  6
set random_seeds  { }
set checkpoint    100000



#############################################################
#  Setup System                                             #
#############################################################

if { [file exists "$name$ident.DHN"] } {
    set DHN_file [open "$name$ident.DHN" "a"]
} else {
    set DHN_file [open "$name$ident.DHN" "w"]
    puts -nonewline $DHN_file "ID int_time pack_i density a_cube re rg rh re2/rg2 Temp mindist "
    puts $DHN_file "p_total D(p_total) p_FENE D(p_FENE) p_lj D(p_lj) p_ideal p_osmotic"; flush $DHN_file
}


# Random number generator setup
#############################################################

if { [llength $random_seeds] > 0 } { eval t_random seed $random_seeds }


# Particle & interaction setup
#############################################################

set i 1
foreach pack_i $packing {
    set n_p_i $N_P; set mpc_i $MPC; set int_time_i $int_time; set int_step_i $int_step
    set n_part $N_T
    set name_i "$name[format %02d $i]"

    set density [expr $pack_i*(6/[PI])]
    set a_cube  [expr pow($N_T/$density,1./3.)]
    setmd box_l $a_cube $a_cube $a_cube
    set bond_l  [expr sqrt(3*[sqr [expr $a_cube/4.]])/($mpc_i+1)]

    puts "\n====================\n=== System [format %2d $i]/[llength $packing] ===\n===================="
    puts "\nSimulate a Diamond Hydrogel Network with $N_node tetra-functional nodes connected by $n_p_i polymer chains with $mpc_i monomers each"
    puts "    in a cubic simulation box of length [setmd box_l] at a density $density which corresponds to a network packing fraction $pack_i."

    if { ![file exists "$name_i$ident.wrm" ] && ![file exists "$name_i$ident.crl" ] && ![file exists "$name_i$ident.end" ] } {
	inter 0 HARMONIC  $fene_k  $fene_r
#	inter 0 FENE      $fene_k  $fene_r
	for {set ia1 0} {$ia1<3} {incr ia1} { for {set ia2 0} {$ia2<3} {incr ia2} { 
	    inter $ia1 $ia2 lennard-jones $lj1_eps $lj1_sig $lj1_cut $lj1_shift 0
	} }
	puts "Interaction Bonds: [inter 0]"

	puts -nonewline "Creating diamond polymers of (initial) bond-length $bond_l... "; flush stdout
	puts "Done ([diamond $a_cube $bond_l $mpc_i counterions $N_CI charges 1.])."
	
	if { $vmd_output=="yes" } {
	    puts -nonewline "Write psf and pdb for VMD connection... "; flush stdout
	    prepare_vmd_connection "$name_i$ident"; puts "Done."
	}
    }


#############################################################
#  Warm-up Integration (with capped LJ-potential)           #
#############################################################

    if { [file exists "$name_i$ident.wrm" ] } {
	set inp [open "$name_i$ident.wrm" r]
	puts -nonewline "\nSkipping warm-up integration: Existing checkpoint found (currently reading it... "; flush stdout
	while { [blockfile $inp read auto] != "eof" } {}
	close $inp; puts "done) with [setmd n_part] particles ($N_T expected)."
	if { $N_T != [setmd n_part] } { puts "WARNING: Configuration does not correspond to current case $i!"; exit }
    } else {
	puts -nonewline "\nStart warm-up integration (capped LJ-interactions) for maximal [expr $warm_step*$warm_loop] timesteps in $warm_loop loops; "
	puts "stop if minimal distance is larger than $min_dist."
	setmd time 0; set tmp_cap $warm_cap1; inter ljforcecap $tmp_cap
	set obs_file [open "$name_i$ident.obs1" "w"]
	puts $obs_file "t mindist re rg rh Temp"
	puts $obs_file "[setmd time] [analyze mindist] [analyze re 8 $n_p_i $mpc_i] [analyze rg] [analyze rh] [setmd temp]"
	puts "    Analysis at t=[setmd time]: mindist=[analyze mindist], re=[analyze re], rg=[analyze rg], rh=[analyze rh], T=[setmd temp]."
	for { set j 0 } { $j < $warm_loop } { incr j } {
	    integrate $warm_step; set tmp_dist [analyze mindist]
	    if { $vmd_output=="yes" } { imd positions }
	    puts -nonewline "    \[$i\] Step [expr ($j+1)*$warm_step]/[expr $warm_step*$warm_loop] (t=[setmd time]): "; flush stdout
	    set tmp_Temp [expr [analyze energy kin]/$n_part/1.5]; puts -nonewline "LJ's cap = $tmp_cap, Temp = $tmp_Temp"; flush stdout
	    puts $obs_file "[setmd time] [analyze mindist] [analyze re] [analyze rg] [analyze rh] $tmp_Temp"
	    puts -nonewline ", mindist=[analyze mindist], re=[analyze re], rg=[analyze rg], rh=[analyze rh]...\r"; flush stdout
	    if { ($tmp_dist >= $min_dist) && ($j > $min_loop) } { break }
	    inter ljforcecap $tmp_cap; set tmp_cap [expr $tmp_cap + $warm_incr]
	}
	# write everything to disk (set checkpoint)
	puts -nonewline "\n    Warm-up complete; saving checkpoint to '$name_i$ident.wrm'... ";flush stdout
	polyBlockWriteAll "$name_i$ident.wrm" "-"; puts "Done."
	flush $obs_file; close $obs_file
    }
 

#############################################################
#      Integration                                          #
#############################################################

    if { [file exists "$name_i$ident.end" ] } {
	set inp [open "$name_i$ident.end" r]
	puts -nonewline "Skipping integration: Existing checkpoint found (currently reading it... "; flush stdout
	while { [blockfile $inp read auto] != "eof" } {}
	close $inp; puts "done) with [setmd n_part] particles ([expr $n_p_i*$mpc_i] expected)."
	if { [expr $n_p_i*$mpc_i] != [setmd n_part] } { puts "WARNING: Configuration does not correspond to current case $i!"; exit }
    } else {
	setmd time 0; set int_loop [expr int($int_time_i/([setmd time_step]*$int_step_i)+0.56)]; set tmp_step 0
	puts "\nStart integration (full interactions) with timestep [setmd time_step] until time t>=$int_time_i (-> $int_loop loops). "
	puts -nonewline "    Activating electrostatics... "; flush stdout
	inter coulomb $bjerrum p3m tune accuracy $accuracy mesh 16
	puts -nonewline "Remove capping of LJ-interactions... "; flush stdout; inter ljforcecap 0; puts "Done."
	set sfx "[expr int(ceil(log10($int_loop*$int_step_i)))+1]d"
	if { [file exists "$name_i$ident.chk" ] } {
	    puts -nonewline "    Checkpoint found (currently reading it... "; flush stdout
	    checkpoint_read "$name_i$ident"
	    set tmp_start [expr int([setmd time]/[setmd time_step]/$int_step_i)]
	    if { [expr $tmp_step/$int_step_i] != $tmp_start } { 
		puts "failed: Checkpoint corrupt, time_step is wrong! Expected: $tmp_start, got: [expr $tmp_step/$int_step_i])"; exit 
	    }
	    puts "done) at time [setmd time]: Skipping ahead to timestep [expr int($tmp_step+1)] in loop $tmp_start!"
	    set obs_file [open "$name_i$ident.obs2" "a"]; analyze set chains 8 $n_p_i $mpc_i
	    set ptot [eval concat [eval concat [analyze pressure]]]; set p1 [lindex $ptot 0]
	    puts "    Analysis at t=[setmd time]: mindist=[analyze mindist], re=[analyze re], rg=[analyze rg], rh=[analyze rh], T=[setmd temp], p=$p1."
	} else {
	    set tmp_start 0; set obs_file [open "$name_i$ident.obs2" "w"]
	    set ptot [eval concat [eval concat [analyze pressure]]]; set p1 [lindex $ptot 0]
	    puts $obs_file "t mindist re rg rh Temp p p2 ideal pid FENE pf pf2 lj plj plj2"
	    puts $obs_file "[setmd time] [analyze mindist] [analyze re 8 $n_p_i $mpc_i] [analyze rg] [analyze rh] [setmd temp] $ptot"
	    puts "    Analysis at t=[setmd time]: mindist=[analyze mindist], re=[analyze re], rg=[analyze rg], rh=[analyze rh], T=[setmd temp], p=$p1."
	    analyze append; checkpoint_set "$name_i$ident.[eval format %0$sfx 0]" "all" "tmp_step"
	}
	for { set j $tmp_start } { $j < $int_loop } { incr j } {
	    integrate $int_step_i; set tmp_dist [analyze mindist]
	    if { $vmd_output=="yes" } { imd positions }
	    set tmp_step [expr ($j+1)*$int_step_i]
	    puts -nonewline "    \[$i\] Step $tmp_step/[expr $int_step_i*$int_loop] (t=[setmd time]): "; flush stdout
	    set tmp_Temp [expr [analyze energy kin]/$n_part/1.5]; puts -nonewline "Temp = $tmp_Temp"; flush stdout
	    set ptot [eval concat [eval concat [analyze pressure]]]; set p1 [lindex $ptot 0]
	    puts $obs_file "[setmd time] [analyze mindist] [analyze re] [analyze rg] [analyze rh] $tmp_Temp $ptot"
	    set tmp_conf [analyze append]
	    # set partial checkpoint (will have previous 'configs' by [analyze append] => averages will be correct)
	    if { [expr $tmp_step % $checkpoint]==0 } {
		puts -nonewline "\r    \[$i\] Step $tmp_step: Checkpoint at time [setmd time]... "; flush stdout; flush $obs_file
		checkpoint_set "$name_i$ident.[eval format %0$sfx $tmp_step]" [expr int($checkpoint/$int_step_i)] "tmp_step" "-"
		puts "set (with <re>=[analyze <re>], <rg>=[analyze <rg>] averaged over $tmp_conf configurations)."
	    } else { puts -nonewline ", mindist=[analyze mindist], re=[analyze re], rg=[analyze rg], rh=[analyze rh], p=$p1...\r"; 
		flush stdout }
	}
	# write everything to disk (set checkpoint)
	# (the whole configs-array is not included here for space constraints (it may exceed 1700MB),
	#  it is however stored fractionally in the partial checkpoints, so use 'checkpoint_read' to restore it)
	puts -nonewline "\n    Integration complete; saving checkpoint to '$name_i$ident.end'... ";flush stdout
	polyBlockWriteAll "$name_i$ident.end" "-" "-"; puts "Done."; close $obs_file

	puts -nonewline "\nFinished with current system; "
	# derive ensemble averages
	lappend what [calcObsAv $name_i$ident.obs2 { 1 5 6 7 9 11 12 14 15 } ]
	set avg [findObsAv { Temp mindist p p2 pid pf pf2 plj plj2 } [lindex $what end]]
	set tmp_Temp [lindex $avg 1]; set tmp_min [lindex $avg 2]
	set p1 [lindex $avg 3]; set p2 [lindex $avg 4]; set pid [lindex $avg 5]; set p_os [expr $p1/$pid]
	set pf1 [lindex $avg 6]; set pf2 [lindex $avg 7]; set plj1 [lindex $avg 8]; set plj2 [lindex $avg 9]
	set d_p12 [expr sqrt(($p2 - $p1*$p1)/([lindex $avg 0]-1))]
	set d_pf12 [expr sqrt(($pf2 - $pf1*$pf1)/([lindex $avg 0]-1))]
	set d_plj12 [expr sqrt(($plj2 - $plj1*$plj1)/([lindex $avg 0]-1))]
	set tmp_re [analyze <re>]; set tmp_rg [analyze <rg>]; set tmp_rh [analyze <rh>]
	set tmp_rat2 [expr $tmp_re*$tmp_re/($tmp_rg*$tmp_rg)]
	puts -nonewline "<re> = $tmp_re, <rg> = $tmp_rg, <rh> = $tmp_rh, "
	puts "<re2>/<rg2> = $tmp_rat2 (RW=6), <Temp> = $tmp_Temp, <p>=$p1+-$d_p12=$p_os."
	# append ensemble averages to .DHN-file
	puts -nonewline $DHN_file "$i $int_time_i $pack_i $density $a_cube "
	puts -nonewline $DHN_file "$tmp_re $tmp_rg $tmp_rh $tmp_rat2 $tmp_Temp $tmp_min "
	puts $DHN_file "$p1 $d_p12 $pf1 $d_pf12 $plj1 $d_plj12 $pid $p_os"; flush $DHN_file
	# sort <g1>, <g2>, and <g3> into .g123-file
	set outG [open "$name_i$ident.g123" "w"]
	for {set gx 1} {$gx<=3} {incr gx} { eval set tmp_g$gx [list [analyze <g$gx>]] }
	for {set gt 0} {$gt<[llength $tmp_g1]} {incr gt} { 
	    puts $outG "[expr $gt*[setmd time_step]] [lindex $tmp_g1 $gt] [lindex $tmp_g2 $gt] [lindex $tmp_g3 $gt]"
	}
	close $outG
	# look at internal distances
	set outI [open "$name_i$ident.idf" "w"]; set tmp_idf [analyze <internal_dist>]
	for {set gt 0} {$gt<[llength $tmp_idf]} {incr gt} { puts $outI "[expr $gt*[setmd time_step]] [lindex $tmp_idf $gt]" }
	close $outI
	# create gnuplots
	puts -nonewline "Creating a gnuplot from current results... "; flush stdout
	plotObs $name_i$ident.obs2 {1:6 1:3 1:4 1:5 1:2} titles {Temp re rg rh mindist} labels [concat "time (tau)" "$name_i$ident.obs2"]
	plotObs $name_i$ident.g123 {1:2 1:3 1:4} titles {<g1> <g2> <g3>} labels [concat "time (tau)" "$name_i$ident.g123"] scale "logscale xy"
	plotObs $name_i$ident.idf {1:2} titles {<internal_dist>} labels [concat "time (tau)" "$name_i$ident.idf"] scale "logscale xy"
	lappend plotted "$name_i$ident.obs2"; lappend plotted "$name_i$ident.g123"; lappend plotted "$name_i$ident.idf"
	puts "Done."
    }
    puts -nonewline "Cleaning up for next system... "; flush stdout; 
    part deleteall; analyze remove; setmd time 0; incr i; puts "Done.\n"
}
# Final gnuplots
puts -nonewline "Creating a gnuplot of the averaged quantities... "; flush stdout
plotObs $name$ident.DHN {3:6 3:7 3:8 3:9} titles {"<re>" "<rg>" "<rh>" "<re2>/<rg2>" } labels { "packing fraction" } scale "logscale xy"
plotObs $name$ident.DHN {3:12 3:14 3:16 3:18 3:19} titles {"<p>" "<p_FENE>" "<p_lj>" "<p_ideal>" "<p_osmotic>"} labels { "packing fraction" }
lappend plotted "$name$ident.DHN"; lappend plotted "$name$ident.pres"; puts "Done."
# puts -nonewline "Combining all plots into '$name_i$ident.final.ps'... "; flush stdout
# plotJoin $plotted "$name_i$ident.final.ps"; puts "Done."
# Wrapping up
puts -nonewline "Closing files... "; close $DHN_file; close $VIR_file; puts "Done."
puts "\nThe Diamond Hydrogel Networks Testcase is now complete.\nThanks for watching, and Good Night!\n"
