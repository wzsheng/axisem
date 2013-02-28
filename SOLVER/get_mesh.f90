!=================
module get_mesh
!=================
!
! This module reads in mesh properties from the mesher (databases meshdb.dat), 
! and allocates related memory.
! The database contains at the global level:
!    elemental control nodes, element type.
! at the solid/fluid level: 
!    mapping from solid/fluid to global element numbers, global numbering 
!    (for solid/fluid subdomains only), solid-fluid boundary element mapping.
!    solid/fluid message-passing mapping arrays and message size indicators;
! and general background model information, time step & period, axial arrays.
! 
use global_parameters
use data_mesh_preloop
 
implicit none

public :: read_db
public :: compute_coordinates_mesh
private

contains

!@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

!-----------------------------------------------------------------------------
subroutine read_db
!
! Read in the database generated by the mesher. File names are 
! meshdb.dat0000, meshdb.dat0001, etc. for nproc-1 processor jobs. 
! These databases must stem from the same meshing as mesh_params.h !!
! 
!-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

use data_mesh
use data_comm
use data_proc
use data_time
use data_io,            ONLY : force_ani
use data_numbering,     ONLY : nglob, nglob_solid, igloc_solid, igloc_fluid
use commun,             ONLY : barrier, psum, pmax, pmin
use background_models,  ONLY : model_is_ani, model_is_anelastic

integer             :: iptp, ipsrc, ipdes, imsg, ipt, inode, iptcp, iel, idom, i
character(len=120)  :: dbname
integer             :: globnaxel, globnaxel_solid, globnaxel_fluid

! Allocate arrays from data_mesh_preloop (only needed before the time loop),
! i.e. to be deallocated before the loop
  allocate(lnods(1:nelem,1:8))
  allocate(eltype(1:nelem), coarsing(1:nelem), north(1:nelem), axis(1:nelem))
  allocate(ielsolid(1:nel_solid))
  allocate(ielfluid(1:nel_fluid))

  dbname = trim(meshpath)//'/meshdb.dat'//appmynum

  do i=0, nproc-1
     call barrier
     if (mynum==i) then
        write(6,*)'  ', procstrg, 'opening database ', trim(dbname)
        open(1000+mynum, file=trim(dbname), FORM="UNFORMATTED", &
                             STATUS="OLD", POSITION="REWIND")
     endif
     call flush(6)
     call barrier
  enddo
  if (lpr) write(6,*)'  Reading databases: see processor output for details.'
  write(69,*)'reading database from ', trim(dbname)

!\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\

   write(69,*)'reading coordinates/control points...'
   read(1000+mynum) npoin

   write(69,*)'global number of control points:',npoin

   allocate(crd_nodes(1:npoin,1:2))

   read(1000+mynum) crd_nodes(:,1)
   read(1000+mynum) crd_nodes(:,2)
   do iptcp = 1, npoin 
      if(abs(crd_nodes(iptcp,2)) < 1.e-8) crd_nodes(iptcp,2) = zero
   end do

   do iel = 1, nelem
      read(1000+mynum) (lnods(iel,inode), inode=1,8)
   end do

! Number of global distinct points (slightly differs for each processor!)
   read(1000+mynum) nglob
   write(69,*)'  global number:',nglob

!  Element type
   read(1000+mynum) eltype
   read(1000+mynum) coarsing

!!!!!!!!!!! SOLID/FLUID !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

! mapping from sol/flu (1:nel_fluid) to global element numbers (1:neltot) 
   write(69,*)'reading solid/fluid domain info...'
   read(1000+mynum) ielsolid
   read(1000+mynum) ielfluid

! Number of distinct points in solid (slightly differs for each processor!)
   read(1000+mynum) nglob_solid

!  slocal numbering 
   read(1000+mynum) igloc_solid(1:npoint_solid)

!  flocal numbering 
   read(1000+mynum) igloc_fluid(1:npoint_fluid)

! Solid-Fluid boundary
   write(69,*)'reading solid/fluid boundary info...'
   read(1000+mynum) have_bdry_elem

   read(1000+mynum) bdry_solid_el(1:nel_bdry)
   read(1000+mynum) bdry_fluid_el(1:nel_bdry)
   read(1000+mynum) bdry_jpol_solid(1:nel_bdry)
   read(1000+mynum) bdry_jpol_fluid(1:nel_bdry)

! General numerical input/output parameters
   write(69,*)'reading numerical parameters...'
   read(1000+mynum) pts_wavelngth,period,courant,deltat
   write(69,*)
   write(69,*)'General numerical input/output parameters==================='
   write(69,*)'  pts/wavelngth=',pts_wavelngth
   write(69,*)'  period [s]=',period
   write(69,*)'  courant=',courant
   write(69,*)'  deltat [s]=',deltat
   write(69,*)

   if (lpr) then 
      write(6,*)  
      write(6,*)'  General numerical input/output parameters================'
      write(6,*)'    grid pts/wavelngth =',pts_wavelngth
      write(6,*)'    source period [s]  =',period
      write(6,*)'    courant number     =',courant
      write(6,*)'    time step [s]      =',deltat
   endif

! Background model
   write(69,*)'reading background model info...'
   read(1000+mynum) bkgrdmodel(1:lfbkgrdmodel)
   bkgrdmodel=bkgrdmodel(1:lfbkgrdmodel)

   read(1000+mynum) router,resolve_inner_shear,have_fluid
   do idom=1,ndisc
      read(1000+mynum) discont(idom),solid_domain(idom),idom_fluid(idom) 
   enddo
 
   if (force_ani) then
      ani_true = .true.
   else
      ani_true = model_is_ani(bkgrdmodel)
   endif

   anel_true = model_is_anelastic(bkgrdmodel)
  
   read(1000+mynum)rmin,minh_ic,maxh_ic,maxh_icb
   write(69,*)
   write(69,*)'Background model============================================'
   write(69,*)'  bkgrdmodel          = ', bkgrdmodel(1:lfbkgrdmodel)
   write(69,*)'  router [m]          = ', router
   write(69,*)'  resolve_inner_shear = ', resolve_inner_shear
   write(69,*)'  have_fluid          = ', have_fluid
   write(69,*)'  ani_true            = ', ani_true
   write(69,*)'  anel_true           = ', anel_true

   if (lpr) then 
      write(6,*)  
      write(6,*)'  Background model========================================='
      write(6,*)'    bkgrdmodel = ', bkgrdmodel(1:lfbkgrdmodel)
      write(6,*)'    radius [m] = ', router
      write(6,*)'    have_fluid = ', have_fluid
   endif

! Min/max grid spacing
   read(1000+mynum)hmin_glob,hmax_glob
   read(1000+mynum)min_distance_dim,min_distance_nondim
   write(69,*)
   write(69,*)'Min/max grid spacing========================================'
   write(69,*)'  hmin          [m]   : ', hmin_glob
   write(69,*)'  hmax          [m]   : ', hmax_glob
   write(69,*)'  min_distance_dim [m]: ', min_distance_dim
   write(69,*)'  min_distance_nondim : ', min_distance_nondim

   hmin_glob=pmax(hmin_glob)
   hmax_glob=pmax(hmax_glob)
   min_distance_dim=pmin(min_distance_dim)
   if (lpr) then
      write(6,*)
      write(6,*)'  Min/max grid spacing====================================='
      write(6,*)'    hmin (global) [m]   : ', hmin_glob
      write(6,*)'    hmax (global) [m]   : ', hmax_glob
      write(6,*)'    min_distance_dim [m]: ', min_distance_dim
      write(6,*)
   endif

! critical ratios h/v min/max and locations
   read(1000+mynum) char_time_max,      char_time_max_globel
   read(1000+mynum) char_time_max_rad,  char_time_max_theta
   read(1000+mynum) char_time_min,      char_time_min_globel
   read(1000+mynum) char_time_min_rad,  char_time_min_theta

   write(69,*)
   write(69,*)'critical ratios max(h/v) and locations=================='
   write(69,*)'  max. charact. time [s]  :', char_time_max
   write(69,*)'  correspond. radius [m]  :', char_time_max_rad*router
   write(69,*)'  correspond. theta [deg] :', char_time_max_theta
   write(69,*)
   write(69,*)'critical ratios min(h/v) and locations=================='
   write(69,*)'  min. charact. time [s] : ', char_time_min
   write(69,*)'  correspond. radius [m] : ', char_time_min_rad*router
   write(69,*)'  correspond. theta [deg]: ', char_time_min_theta
   write(69,*)

! Axial element arrays
   read(1000+mynum) have_axis
   read(1000+mynum) naxel, naxel_solid, naxel_fluid
   write(69,*)
   write(69,*) 'Axial elements (glob,sol,flu): ', naxel, naxel_solid, naxel_fluid

   if (lpr) write(6,*)'  Axialogy================================================='
   call barrier

   do i=0, nproc-1
      call barrier
      if (mynum==i) then 
         if (have_axis) then
            write(6,11)procstrg,naxel,naxel_solid,naxel_fluid
            write(69,*)'      number of total axial elements:',naxel
            write(69,*)'      number of solid axial elements:',naxel_solid
            write(69,*)'      number of fluid axial elements:',naxel_fluid
            if (naxel == 0 .or. naxel_solid == 0 .and. naxel_fluid == 0) then 
               write(6,*)'PROBLEM: Logically supposed to have the axis &
                                  & but have no axial elements!'
               stop
            endif
         else
            write(6,*)'    WARNING!',procstrg,'does not touch the axis!'
            write(6,*)'      number of total axial elements:',naxel
            write(6,*)'      number of solid axial elements:',naxel_solid
            write(6,*)'      number of fluid axial elements:',naxel_fluid
            if (naxel > 0 .or. naxel_solid > 0 .or. naxel_fluid > 0) then 
               write(6,*)'PROBLEM: Logically not supposed to have the axis &
                                  & but have some axial elements!'
               stop
            endif
         endif
      endif
      call barrier
   enddo

11 format('     ',a8,'has',i6,' axial elements (',i6,' solid,',i4,' fluid)')

   globnaxel=int(psum(real(naxel,kind=realkind)))
   globnaxel_solid=int(psum(real(naxel_solid,kind=realkind)))
   globnaxel_fluid=int(psum(real(naxel_fluid,kind=realkind)))
   if (lpr) then 
      write(6,*)
      write(6,*)'    Global total axial elements:',globnaxel
      write(6,*)'    Global solid axial elements:',globnaxel_solid
      write(6,*)'    Global fluid axial elements:',globnaxel_fluid
      write(6,*)
   endif

   allocate(ax_el(naxel),ax_el_solid(1:naxel_solid),ax_el_fluid(1:naxel_fluid))

   read(1000+mynum) ax_el(1:naxel)
   read(1000+mynum)ax_el_solid(1:naxel_solid)
   read(1000+mynum)ax_el_fluid(1:naxel_fluid)

! mask s-coordinate of axial elements identically to zero
   if (lpr) write(6,*)'  setting s coordinate identical to zero along axis...'
   do iel=1, naxel
     crd_nodes(lnods(ax_el(iel),1),1) = zero
     crd_nodes(lnods(ax_el(iel),7),1) = zero
     crd_nodes(lnods(ax_el(iel),8),1) = zero
   enddo

   write(69,*)'reading communication info...'
   write(69,*)

! SOLID message passing SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS
   read(1000+mynum) sizerecv_solid
   write(69,*) 'number of solid messages received:', sizerecv_solid
   if ( sizerecv_solid > 0) then 
     allocate(listrecv_solid(1:sizerecv_solid))
     listrecv_solid(:) = -1
     
     allocate(sizemsgrecv_solid(1:sizerecv_solid))
     sizemsgrecv_solid(:) = 0
     
     read(1000+mynum) listrecv_solid(:)
     read(1000+mynum) sizemsgrecv_solid(:)
     sizemsgrecvmax_solid = maxval(sizemsgrecv_solid(:))
     
     write(69,*) 'max size of solid messages received:', sizemsgrecvmax_solid
    
    allocate(glocal_index_msg_recv_solid(1:sizemsgrecvmax_solid,1:sizerecv_solid))
     glocal_index_msg_recv_solid(:,:) = 0
     
     allocate(buffr_solid(1:sizemsgrecvmax_solid,1:3))
     allocate(buffr_all(1:sizemsgrecvmax_solid,1:3,1:sizerecv_solid))
     buffr_all(:,:,:) = 0.

     do imsg = 1, sizerecv_solid
       ipsrc = listrecv_solid(imsg) 
       do iptp = 1, sizemsgrecv_solid(imsg)
          read(1000+mynum) glocal_index_msg_recv_solid(iptp,imsg)
       end do
     end do
   end if

   read(1000+mynum) sizesend_solid
   write(69,*) 'number of solid messages sent:', sizesend_solid
   if ( sizesend_solid > 0) then 
     allocate(listsend_solid(1:sizesend_solid))
     listsend_solid(:) = -1
     
     allocate(sizemsgsend_solid(1:sizesend_solid))
     sizemsgsend_solid(:) = 0
     
     read(1000+mynum) listsend_solid(:)
     read(1000+mynum) sizemsgsend_solid(:) 
     sizemsgsendmax_solid = maxval(sizemsgsend_solid(:))
     
     write(69,*) 'max size of solid messages sent:', sizemsgsendmax_solid
     
     allocate(glocal_index_msg_send_solid(1:sizemsgsendmax_solid,1:sizesend_solid))
     glocal_index_msg_send_solid(:,:) = 0
     
     allocate(buffs_solid(1:sizemsgsendmax_solid,1:3))
     allocate(buffs_all(1:sizemsgsendmax_solid,1:3,1:sizesend_solid))
     buffs_all(:,:,:) = 0.

     do imsg = 1, sizesend_solid
       ipdes = listsend_solid(imsg)
       do iptp = 1, sizemsgsend_solid(imsg)
        read(1000+mynum) glocal_index_msg_send_solid(iptp,imsg)
       end do
     end do
   end if
 
! FLUID message passing FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
   if (have_fluid) then
      read(1000+mynum) sizerecv_fluid
      write(69,*)'number of fluid messages received:', sizerecv_fluid
      if ( sizerecv_fluid > 0) then 
         allocate(listrecv_fluid(1:sizerecv_fluid))
         listrecv_fluid(:) = -1

         allocate(sizemsgrecv_fluid(1:sizerecv_fluid)) 
         sizemsgrecv_fluid(:) = 0

         read(1000+mynum) listrecv_fluid(:)
         read(1000+mynum) sizemsgrecv_fluid(:) 
         sizemsgrecvmax_fluid = maxval(sizemsgrecv_fluid(:))
         
         write(69,*)'max size of fluid messages received:',sizemsgrecvmax_fluid
         
         allocate(glocal_index_msg_recv_fluid(1:sizemsgrecvmax_fluid,1:sizerecv_fluid))
         glocal_index_msg_recv_fluid(:,:) = 0
         allocate(buffr_fluid(1:sizemsgrecvmax_fluid))
         
         do imsg = 1, sizerecv_fluid
            ipsrc = listrecv_fluid(imsg) 
            do iptp = 1, sizemsgrecv_fluid(imsg)
               read(1000+mynum) glocal_index_msg_recv_fluid(iptp,imsg)
            end do
         end do
      end if

      read(1000+mynum) sizesend_fluid
      write(69,*) '# fluid messages sent:', sizesend_fluid
      
      if ( sizesend_fluid > 0) then 
         allocate(listsend_fluid(1:sizesend_fluid))
         listsend_fluid(:) = -1
         
         allocate(sizemsgsend_fluid(1:sizesend_fluid)) 
         sizemsgsend_fluid(:) = 0
         
         read(1000+mynum) listsend_fluid(:)
         read(1000+mynum) sizemsgsend_fluid(:) 
         
         sizemsgsendmax_fluid = maxval(sizemsgsend_fluid(:))
         write(69,*)'max size of fluid messages sent:',sizemsgsendmax_fluid
         allocate(glocal_index_msg_send_fluid(1:sizemsgsendmax_fluid,1:sizesend_fluid))
         glocal_index_msg_send_fluid(:,:) = 0
         allocate(buffs_fluid(1:sizemsgsendmax_fluid))

         do imsg = 1, sizesend_fluid
            ipdes = listsend_fluid(imsg)
            do iptp = 1, sizemsgsend_fluid(imsg)
               read(1000+mynum) glocal_index_msg_send_fluid(iptp,imsg)
            end do
         end do
      end if
   endif ! have_fluid

!/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/

  write(69,*) 'Successfully read parallel database'

  do i=0, nproc-1
     call barrier
     if (mynum==i) then
        write(6,*) '  ', procstrg,'closing database ', trim(dbname)
        call flush(6)
        write(69,*)'Closed the database'
        close(1000+mynum)
     endif
     call barrier
  enddo
  call flush(6)
  write(69,*)
  if (lpr) write(6,*)

end subroutine read_db
!=============================================================================

!-----------------------------------------------------------------------------
subroutine compute_coordinates_mesh(s,z,ielem,inode)
!
! Output s,z are the physical coordinates defined at
! serendipity nodes inode (between 1 and 8 usually) 
! for (global) element ielem
!
!-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
 
integer, intent(in)           :: ielem, inode
double precision, intent(out) :: s,z

  s = crd_nodes(lnods(ielem,inode),1)
  z = crd_nodes(lnods(ielem,inode),2)

end subroutine compute_coordinates_mesh
!=============================================================================

!@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

!=====================
end module get_mesh
!=====================
