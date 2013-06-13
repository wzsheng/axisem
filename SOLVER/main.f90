!===================
program axisem 
!===================

  use data_proc,      ONLY : nproc, mynum, appnproc, appmynum, lpr, procstrg
  use data_io,        ONLY : dump_xdmf, use_netcdf
  use nc_routines,    ONLY : nc_end_output, nc_open_parallel 
  use data_source,    ONLY : isim,num_simul
  use data_mesh,      ONLY : do_mesh_tests
  use parameters,     ONLY : open_local_param_file, readin_parameters
  use get_mesh,       ONLY : read_db 
  use def_grid,       ONLY : init_grid, mesh_tests, deallocate_preloop_arrays
  use time_evol_wave, ONLY : prepare_waves, time_loop
  use commun,         ONLY : pinit, pend, barrier
  use meshes_io,      ONLY : finish_xdmf_xml
  
  implicit none

  call set_ftz() ! ftz.c, set flush to zero

  call pinit ! commun
  call define_io_appendix(appmynum,mynum)
  call define_io_appendix(appnproc,nproc)
  call open_local_param_file ! parameters, open file for processor-specific screen output 
  call start_clock !clocks

  if (lpr) write(6,*) 'MAIN: Reading parameters..................................'
  call readin_parameters ! parameters
  
  !if(use_netcdf) then
  !  if (lpr) write(6,*)'MAIN: Prepare netcdf files for wavefield output ..........'
  !  call nc_create_outputfile
  !  if (lpr)  write(6,*)'MAIN: netcdf file prepared ...............................'
  !end if
  
  if (lpr) write(6,*) 'MAIN: Reading mesh database...............................'
  call read_db  ! get_mesh

  if (lpr) write(6,*) 'MAIN: Initializing grid...................................'
  call init_grid ! def_grid

  if (do_mesh_tests) then
     if (lpr) write(6,*) 'MAIN: Testing the mesh....................................'
     call mesh_tests ! def_grid
  endif 

  if (num_simul .ne. 1) then
     write(6,*) 'ERROR: implementation of multiple simulations within one run'
     write(6,*) '       not finished yet.'
     write(6,*) '       For now set number of simulations in inparam to 1, splitting '
     write(6,*) '       to the different sources is then done by the submit script.'
     stop 2
  endif

  do isim=1, num_simul

     if (lpr) write(6,*) 'MAIN: Starting wave preparation...........................'
     call prepare_waves ! time_evol_wave

     ! Deallocate all the large arrays that are not needed in the time loop,
     ! specifically those from data_mesh_preloop and data_pointwise
     if (lpr) write(6,*) 'MAIN: Deallocating arrays not needed in the time loop.....'
     call deallocate_preloop_arrays ! def_grid
 
     if (use_netcdf) then
        if (lpr) write(6,*) 'MAIN: Opening Netcdf file for parallel output.............'
        call nc_open_parallel()
     endif
    
     call barrier ! Just making sure we're all ready to rupture...
     
     if (lpr) write(6,*) 'MAIN: Starting wave propagation...........................'
     call time_loop ! time_evol_wave
  enddo

  if (use_netcdf) then
     if (lpr) write(6,*) 'MAIN: Flush and close all netcdf files ...................'
     call nc_end_output ! Dump receiver seismograms to finalize netcdf output 
  end if
  
  if (dump_xdmf) then
     if (lpr) write(6,*)'MAIN: Finishing xdmf xml file...'
     call finish_xdmf_xml() ! meshes_io
  endif

  call end_clock ! clocks

  call pend ! commun

  write(6,*) procstrg, '=========PROGRAM axisem FINISHED============='

  write(69,*) '=========PROGRAM axisem FINISHED============='

!=======================
end program axisem
!=======================


!-----------------------------------------------------------------------------
subroutine start_clock
  !
  ! Driver routine to start the timing, using the clocks_mod module.
  !
  !-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

  use data_time, ONLY : idcomm, iddump, idmpi, idnbio, idold, idstiff, idanelts, idanelst
  use data_proc, ONLY : lpr, mynum
  use clocks_mod, ONLY : clock_id, clocks_init
  
  implicit none
  
  character(len=8)  :: mydate
  character(len=10) :: mytime

  call date_and_time(mydate,mytime) 
  if (lpr) then
     write(6,*)
     write(6,*)':::::::::::::::::::::::::::::::::::::::::::&
                &:::::::::::::::::::::::::::'
     write(6,11) mydate(5:6),mydate(7:8),mydate(1:4),mytime(1:2),mytime(3:4)
     write(6,*)
  endif

11 format('     Simulation started on ', A2,'/',A2,'/',A4,' at ',&
          A2,'h ',A2,'min')

  write(69,11) mydate(5:6),mydate(7:8),mydate(1:4),mytime(1:2),mytime(3:4)
  write(69,*)

  call clocks_init(mynum)
  idold    = clock_id('Time loop routine')
  idcomm   = clock_id('Assembly/MPI routines')
  idmpi    = clock_id(' > Only MPI routine')
  idstiff  = clock_id('Solid stiffness routine')
  idanelst = clock_id(' > Anelastic stiffness routine')
  idanelts = clock_id('Anelastic time step routine')
  iddump   = clock_id('Dump routine')
  idnbio   = clock_id('Non Blocking IO red light')

  if (lpr) then 
     write(6,*)'::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::'
     write(6,*)
  endif

end subroutine start_clock
!=============================================================================

!-----------------------------------------------------------------------------
subroutine end_clock 
  !
  ! Wapper routine to end timing and display clock informations.
  !
  !-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

  use clocks_mod, ONLY : clocks_exit
  use data_proc,  ONLY : mynum

  implicit none

  if(mynum==0) then
     write(6,*)
     write(6,"(10x,'Summary of timing measurements:')")
     write(6,*)
  endif

  call clocks_exit(mynum)

  if(mynum==0) write(6,*)

end subroutine end_clock
!=============================================================================

!-----------------------------------------------------------------------------
subroutine define_io_appendix(app,iproc)
  !
  ! Defines the 4 digit character string appended to any 
  ! data or io file related to process myid. 
  !
  !-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

  implicit none
  integer, intent(in)           :: iproc
  character(len=4), intent(out) :: app
  
  write(app,"(I4.4)") iproc

end subroutine define_io_appendix
!=============================================================================

!-----------------------------------------------------------------------------
!subroutine flush(iunit)
!
! Pseudo flush routine, in case flush is not supported
! by compiler. Comment out/Remove if flush supported by compiler.
!
!-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
!
!  implicit none
!  integer :: iunit
!
!  iunit=iunit
!
!end subroutine flush
!=============================================================================
