!----------------------------------------------------------------------------
subroutine calcmdefect()  
!----------------------------------------------------------------------------
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! mpi
USE mp_images,     ONLY : nimage
USE mp_bands,      ONLY : nbgrp
USE mp_pools,      ONLY : npool
USE mp_pools, ONLY: inter_pool_comm, intra_pool_comm, nproc_pool, me_pool
USE mp_bands, ONLY: intra_bgrp_comm
USE mp, ONLY: mp_sum, mp_gather, mp_bcast, mp_get
!include mpif.h

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! control
USE kinds, ONLY: DP,sgl
USE plugin_flags, ONLY : use_calcmdefect 
USE control_flags,    ONLY : gamma_only, io_level
USE run_info,  ONLY: title    ! title of the run

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! extra function
USE noncollin_module, ONLY : noncolin
USE spin_orb,         ONLY : lspinorb
USE lsda_mod, ONLY: lsda, nspin
USE ldaU, ONLY : eth

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! scf
USE ions_base, ONLY : nat, ntyp => nsp, ityp, tau, zv, atm
USE cell_base, ONLY: omega, alat, tpiba2, at, bg, tpiba
USE constants, ONLY: tpi, e2, eps6,pi
USE ener, ONLY: ewld, ehart, etxc, vtxc, etot, etxcc, demet, ef
USE fft_base,  ONLY: dfftp, dffts
USE fft_interfaces, ONLY : fwfft, invfft
USE gvect, ONLY: ngm, gstart, g, gg, gcutm, igtongl
USE klist , ONLY: nks, nelec, xk, wk, degauss, ngauss, igk_k, ngk
USE scf, ONLY: rho, rho_core, rhog_core, v, vltot, vrs
USE vlocal, ONLY: vloc, strf
USE wvfct, ONLY: npwx, nbnd, wg, et
USE gvecw, ONLY: ecutwfc
USE uspp, ONLY: nkb, vkb, dvan
USE uspp_param, ONLY: nh
USE wavefunctions, ONLY : evc,evc1,evc2,evc3,evc4, psic, psic1, psic2, psic3, psic4
USE fft_types, ONLY:  fft_index_to_3d



!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
USE ener, ONLY:  eband, deband !rg_spin
USE wvfct, ONLY: g2kin !rg_spin
USE uspp, ONLY:  dvan_so !rg_spin
USE upf_spinorb, ONLY: fcoef !rg_spin
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!use init_us_2, only: init_us_2_perturb

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! io
USE io_global, ONLY: stdout, ionode, ionode_id
USE io_files, ONLY: nd_nmbr, nwordwfc, iunwfc, prefix, tmp_dir, seqopn, iuntmp
USE clib_wrappers,     ONLY: md5_from_file
USE buffers,          ONLY : open_buffer,get_buffer, close_buffer, save_buffer
USE HDF5
!use input_parameters, only: vperturb_filename,eps_filename, &
!kpoint_initial ,kpoint_final ,bnd_initial ,bnd_final ,&
!calcmlocal ,calcmnonlocal ,calcmcharge 
IMPLICIT NONE


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! control
INTEGER, EXTERNAL :: find_free_unit
INTEGER :: tmp_unit
INTEGER  :: ios
INTEGER, PARAMETER :: n_overlap_tests = 12
REAL(dp), PARAMETER :: machine_eps = 1.d-4
INTEGER, PARAMETER :: io = 77, iob = 78

 CHARACTER(len=32)::vf_md5_cksum="NA"
 CHARACTER(len=32)::epsf_md5_cksum="NA"
 CHARACTER(len=32)::epsmat_q0_f_md5_cksum="NA"
 CHARACTER(len=32)::epsmat_q1_f_md5_cksum="NA"
 CHARACTER(len=32)::ctlf_md5_cksum="NA"
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! scf
INTEGER :: npw, ig, ibnd, ik, ispin, nbndup, nbnddown, &
nk , ikk,ikk0,  inr, ig1, ig2,iq
INTEGER :: j,   na, nt, ijkb0, ikb,jkb, ih,jh, ik0,ibnd0
INTEGER, ALLOCATABLE :: idx(:), igtog(:), gtoig(:)
LOGICAL :: exst
REAL(DP) :: ek, eloc, enl, etot_

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! parallization
! number of g vectors (union of all k points)
INTEGER ngtot_l ! on this processor
INTEGER, ALLOCATABLE :: ngtot_d(:), ngtot_cumsum(:), indx(:)
INTEGER ngtot_g ! sum over processors
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! parallization
REAL(DP), ALLOCATABLE :: g_l(:,:), g_g(:,:), g2(:)
COMPLEX(DP), ALLOCATABLE :: evc_l(:), evc_g(:), evc_g2(:), avc_tmp(:,:,:), cavc_tmp(:,:,:)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! intermediate data
COMPLEX(DP), ALLOCATABLE :: aux(:), auxr(:), auxg(:), psiprod(:),vgk(:),vgk_perturb(:),vkb_perturb(:,:)
COMPLEX(DP) :: mnl, ml,mltot,mltot1,mltot2,mnltot,psicnorm,psicprod,enl1,phaseft,psicprod1
COMPLEX(DP) ::  ml_up, ml_down, mnl_d, mnl_p ! rg_spin
LOGICAL :: offrange
REAL(dp)::arg,argt,argt2
COMPLEX(DP)::phase
INTEGER:: irx,iry,irz
INTEGER:: irx2,iry2,irz2
INTEGER:: irx1,iry1,irz1

INTEGER :: ix0,ix1,ix2
INTEGER :: iy0,iy1,iy2
INTEGER :: iz0,iz1,iz2, ikpsi0, ikpsi1, ikpsi2
COMPLEX(DP)::vlfft
COMPLEX(DP) ::  ml0,ml1,ml2, ml3,ml4,ml5,ml6,ml7
 

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!! vl  supercell
integer ::  unit_pert !rg_spin
character (len=75) ::  perturb_file_name!rg_spin
integer :: iunpot_perturb
character (len=75) :: filpot_perturb
character (len=75) :: title_perturb
character (len=3) ,allocatable :: atm_perturb(:)
integer :: nr1x_perturb, nr2x_perturb, nr3x_perturb, nr1_perturb, nr2_perturb, nr3_perturb, &
nat_perturb, ntyp_perturb, ibrav_perturb, plot_num_perturb,  i_perturb,nkb_perturb
integer :: iunplot_perturb, ios_perturb, ipol_perturb, na_perturb, nt_perturb, &
ir_perturb, ndum_perturb
real(DP) :: celldm_perturb (6), gcutm_perturb, dual_perturb, ecut_perturb,  at_perturb(3,3), omega_perturb, alat_perturb
integer, allocatable:: ityp_perturb (:)
real(DP),allocatable:: zv_perturb (:), tau_perturb (:, :)  , plot_perturb (:)
real(DP),allocatable::  V_loc(:,:) !rg_spin
integer :: ir1mod,ir2mod,ir3mod,irnmod
real(DP):: d1,d2,d3

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! charge
COMPLEX(DP), ALLOCATABLE ::  mlat1(:),mlat2(:)
INTEGER :: iscx, iscy,nscx,nscy
REAL(dp)::k0screen, kbT,deltak,deltakG0,deltakG, qxy,qz,lzcutoff
INTEGER:: icount,jcount,kcount
real(DP):: mscreen,mcharge, rmod
INTEGER:: Nlzcutoff,iNlzcutoff,flag1,flag2, nNlzcutoff,Ngzcutoff
!!!!! eps data file 
integer :: nepslines
real(DP),allocatable:: eps_data (:,:)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

          CHARACTER(LEN=256) :: vperturb_filename='vloc.dat'
          CHARACTER(LEN=256) :: eps_filename='eps.dat'
          CHARACTER(LEN=256) :: epsmat_q0_filename='eps0mat.h5'
          CHARACTER(LEN=256) :: epsmat_q1_filename='epsmat.h5'
!          CHARACTER(LEN=256) :: calcmcontrol
          INTEGER :: kpoint_initial 
          INTEGER :: kpoint_final 
          INTEGER :: bnd_initial 
          INTEGER :: bnd_final 
          LOGICAL :: calcmlocal =.false.
          LOGICAL :: calcmnonlocal =.false.
          LOGICAL :: calcmcharge =.false.
          LOGICAL :: mcharge_dolfa =.false.
          REAL :: k0screen_read=0.0

!rg_spin
          character(len=256) :: V_0_filename = 'none', Bxc_1_filename='none', Bxc_2_filename='none', Bxc_3_filename='none'
          character(len=256) :: V_p_filename='none'
          character(len=256) :: V_up_filename='none', V_down_filename='none'
!rg_spin



!!!!!!!!!!hdf5
  CHARACTER(LEN=256) :: h5filename      ! Dataset name
  CHARACTER(LEN=256) :: h5datasetname = "matrix-diagonal"     ! Dataset name
 INTEGER     ::   h5rank,h5error ! Error flag
  !INTEGER     ::  i, j
!  real(dp), DIMENSION(3,1465,2) :: h5dataset_data, data_out ! Data buffers
!  real(dp), DIMENSION(3,1465,2) :: h5dataset_data, data_out ! Data buffers
  real(dp), allocatable :: h5dataset_data_double(:), data_out(:)
  integer, allocatable :: h5dataset_data_integer(:)
  INTEGER(HSIZE_T), allocatable :: h5dims(:),h5maxdims(:)


!  real(dp), allocatable :: gw_epsmat_diag_data(:,:,2),  gw_eps0mat_diag_data(:,:,2)
  real(dp), allocatable :: gw_epsmat_diag_data_q1(:,:,:),  gw_epsmat_diag_data_q0(:,:,:)
  !complex(dp), allocatable :: gw_epsmat_diag_data(:,:,:),  gw_eps0mat_diag_data(:,:,:)
!  real(dp), allocatable :: gw_epsmat_full_data(:,1,1,:,:,2),  gw_eps0mat_full_data(:,1,1,:,:,2)
  real(dp), allocatable :: gw_epsmat_full_data_q1(:,:,:,:,:,:),  gw_epsmat_full_data_q0(:,:,:,:,:,:)
!  real(dp), allocatable :: gw_epsallmat_full_data(:,1,1,:,:,2)
  real(dp), allocatable :: gw_epsmat_full_data_qall(:,:,:,:,:,:)

  real(dp), allocatable :: gw_vcoul_data_q1(:,:),gw_qpts_Data_q1(:,:)
  real(dp), allocatable :: gw_blat_data_q1(:),gw_bvec_Data_q1(:,:)
  integer, allocatable :: gw_gind_eps2rho_data_q1(:,:), gw_gind_rho2eps_data_q1(:,:),gw_nmtx_data_q1(:)

!q0
  real(dp), allocatable :: gw_vcoul_data_q0(:,:),gw_qpts_Data_q0(:,:)
  real(dp), allocatable :: gw_blat_data_q0(:),gw_bvec_Data_q0(:,:)
  integer, allocatable :: gw_gind_eps2rho_data_q0(:,:), gw_gind_rho2eps_data_q0(:,:),gw_nmtx_data_q0(:)
!q0

  integer :: h5dims1(1),h5dims2(2),h5dims3(3),h5dims4(4),h5dims5(5),h5dims6(6)

   integer, allocatable :: gw_grho_data_q1(:),  gw_geps_data_q1(:),gw_g_components_data_q1(:,:)
  integer, allocatable :: gw_nq_data_q1(:),gw_nmtx_max_data_q1(:),gw_fftgrid_data_q1(:),gw_qgrid_data_q1(:),gw_ng_data_q1(:)

!q0
   integer, allocatable :: gw_grho_data_q0(:),  gw_geps_data_q0(:),gw_g_components_data_q0(:,:)
  integer, allocatable :: gw_nq_data_q0(:),gw_nmtx_max_data_q0(:),gw_fftgrid_data_q0(:),gw_qgrid_data_q0(:),gw_ng_data_q0(:)
!q0


!  integer(i8b), allocatable :: gw_nqi8(:)

    real(DP),allocatable ::gw_qabs_q1(:)
    INTEGER :: gw_q_g_commonsubset_size_q1
    integer(DP),allocatable ::gw_q_g_commonsubset_indinrho_q1(:)

!q0
    real(DP),allocatable ::gw_qabs_q0(:)
    INTEGER :: gw_q_g_commonsubset_size_q0
    integer(DP),allocatable ::gw_q_g_commonsubset_indinrho_q0(:)
!q0


!!!!!!!!!!!!!!!!!!
    integer(DP),allocatable ::gind_rho2psi_gw(:)
    real(DP) ::gvec_gw(3)
    integer(DP),allocatable ::gind_psi2rho_gw(:)

    integer(DP),allocatable ::gind_rho2psi_gw_q0(:)
    real(DP) ::gvec_gw_q0(3)
    integer(DP),allocatable ::gind_psi2rho_gw_q0(:)

    integer(DP),allocatable ::gind_rho2psi_gw_q1(:)
    real(DP) ::gvec_gw_q1(3)
    integer(DP),allocatable ::gind_psi2rho_gw_q1(:)
!!!!!!!!!!!!!!!!!!









!    INTEGER :: gind_gw_eps
!!!!!!!!!!hdf5

          NAMELIST / calcmcontrol / vperturb_filename,eps_filename, kpoint_initial, kpoint_final, &
                                 bnd_initial, bnd_final, calcmlocal,calcmnonlocal,calcmcharge, mcharge_dolfa,k0screen_read,& 
                                 V_0_filename, Bxc_1_filename, Bxc_2_filename, Bxc_3_filename, V_p_filename,&  !rg_spin
                                 V_up_filename, V_down_filename  !rg_spin

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!rg_spin
type :: V_file 
   integer :: unit 
   character (len=75) :: filename
   character (len=75) :: title
   character (len=3) ,allocatable :: atm(:)
   integer :: nr1x, nr2x, nr3x, nr1, nr2, nr3, &
   nat, ntyp, ibrav, plot_num,  i,nkb
   integer :: iunplot, ios, ipol, na, nt, &
   ir, ndum
   real(DP) :: celldm(6), gcutm, dual, ecut,  at(3,3), omega, alat
   integer, allocatable:: ityp(:)
   real(DP),allocatable:: zv(:), tau(:, :)  , plot(:)
end type V_file


!type(V_file) :: V_0, Bxc_1, Bxc_2, Bxc_3
!V_0%unit = find_free_unit()
!Bxc_1%unit = find_free_unit()
!Bxc_2%unit = find_free_unit()
!Bxc_3%unit = find_free_unit()
!ALLOCATE ( g2kin(npwx) )
                                 
    Nlzcutoff=dffts%nr3/2
    lzcutoff=Nlzcutoff*alat/dffts%nr1
IF ( use_calcmdefect ) THEN
   IF ( noncolin ) THEN
      if ( lspinorb ) then
         call calcmdefect_soc()
      else
         call calcmdefect_noncolin() 
      endif
  ! ELSE IF (lsda) THEN
  !    call calcmdefect_lsda()
   ELSE   
      call calcmdefect_all()
   ENDIF
ENDIF
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!
!
!
!
!IF ( use_calcmdefect ) THEN
!    call calcmdefect_all()
!ENDIF

CONTAINS 
 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!IO


   subroutine read_perturb_file(v_file_)

      type(V_file) :: v_file_
      integer :: v_file_i_, v_file_ipol_, v_file_nt_, v_file_ir_, v_file_na_

      v_file_%unit = find_free_unit()
      open (unit = v_file_%unit, file = v_file_%filename, form = 'formatted', &
      status = 'old', err = 99, iostat = v_file_%ios)
   99 call errore ('mloc', 'opening file '//TRIM(v_file_%filename), abs (v_file_%ios) )

      read (v_file_%unit, '(a)') v_file_%title
      read (v_file_%unit, * ) v_file_%nr1x, v_file_%nr2x, v_file_%nr3x,&
      v_file_%nr1, v_file_%nr2, v_file_%nr3, v_file_%nat, v_file_%ntyp
    
      allocate(v_file_%plot ( v_file_%nr1*v_file_%nr2*v_file_%nr3))
      allocate(v_file_%ityp (v_file_%nat))
      allocate(v_file_%zv (v_file_%ntyp))
      allocate(v_file_%atm (v_file_%ntyp))
      allocate(v_file_%tau (3,v_file_%nat))
    
      read (v_file_%unit, * ) v_file_%ibrav, v_file_%celldm
      if (v_file_%ibrav == 0) then
         do v_file_i_ = 1,3
            read ( v_file_%unit, * ) ( v_file_%at(v_file_ipol_,v_file_i_),v_file_ipol_=1,3 )
         enddo
         v_file_%alat=v_file_%celldm(1)
      else
         call latgen(v_file_%ibrav,v_file_%celldm,v_file_%at(1,1),v_file_%at(1,2),v_file_%at(1,3),v_file_%omega)
         v_file_%at(:,:)=v_file_%at(:,:)/alat
      endif
      read (v_file_%unit, * ) v_file_%gcutm, v_file_%dual, v_file_%ecut, v_file_%plot_num
      read (v_file_%unit, '(i4,3x,a2,3x,f5.2)') &
            (v_file_nt_, v_file_%atm(v_file_nt_), v_file_%zv(v_file_nt_), v_file_nt_=1, v_file_%ntyp)
      read (v_file_%unit, *) (v_file_%ndum,  (v_file_%tau (v_file_ipol_, v_file_na_), v_file_ipol_ = 1, 3 ), &
         v_file_%ityp(v_file_na_), v_file_na_ = 1, v_file_%nat)
      read (v_file_%unit, * ) (v_file_%plot (v_file_ir_), v_file_ir_ = 1, v_file_%nr1 * v_file_%nr2 * v_file_%nr3)
      v_file_%tau(:,:)=v_file_%tau(:,:)*v_file_%alat/alat

      CALL md5_from_file(v_file_%filename, vf_md5_cksum)
      write (*,*) 'potential files:',TRIM(v_file_%filename),'  MD5 sum:',vf_md5_cksum

      
   end subroutine read_perturb_file

   subroutine get_vloc_colin(V_0, Bxc_3, V_loc)
      type(V_file) :: V_0, Bxc_3
      real(DP) :: V_loc(:,:)

     ! allocate(V_loc( V_0%nr1 * V_0%nr2 * V_0%nr3, 2))

      V_loc(:, 1) = V_0%plot(:) + Bxc_3%plot(:)
      V_loc(:, 2) = V_0%plot(:) - Bxc_3%plot(:)

      
   end subroutine get_vloc_colin

!   subroutine get_vloc_noncolin(V_0, Bxc_3)
!      type(V_file) :: V_0, Bxc_1, Bxc_2, Bxc_3
!      complex(DP), allocatable:: get_vloc_noncolin(:, 4)
!
!      allocate(get_vloc_noncolin( V_0%nr1 * Bxc_1%nr2 * Bxc_3%nr3))

      
!   end subroutine get_vloc_noncolin



  
      



subroutine h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
  CHARACTER(LEN=256) :: h5groupname = "/mats"     ! Dataset name
  CHARACTER(LEN=256) :: h5name_buffer 
  INTEGER(HID_T) :: h5file_id       ! File identifier
  INTEGER(HID_T) :: h5group_id       ! Dataset identifier
  INTEGER(HID_T) :: h5dataset_id       ! Dataset identifier
  INTEGER(HID_T) :: h5datatype_id       ! Dataset identifier
  INTEGER(HID_T) :: h5dataspace_id

  INTEGER :: h5dataype       ! Dataset identifier
 
  CHARACTER(LEN=256) :: h5filename      ! Dataset name
  CHARACTER(LEN=256) :: h5datasetname      ! Dataset name
  real(dp), allocatable :: h5dataset_data_double(:), data_out(:)
  integer, allocatable :: h5dataset_data_integer(:)
  LOGICAL :: h5flag,h5flag_integer,h5flag_double           ! TRUE/FALSE flag to indicate 
  INTEGER(HSIZE_T), allocatable :: h5dims(:),h5maxdims(:)
  INTEGER     ::   h5rank,h5nmembers,i,h5datasize
  INTEGER     ::   h5error ! Error flag
  INTEGER(HID_T) :: file_s1_t,h5_file_datatype 
  INTEGER(HID_T) :: mem_s1_t  ,h5_mem_datatype  
  INTEGER(HID_T) :: debugflag=00
  CALL h5open_f(h5error)
  if (h5error<debugflag) then
    write(*,*)  'h5error',h5error
  elseif (h5error<0) then 
    return(h5error)
  endif
  
    !h5 file
    CALL h5fopen_f (h5filename, H5F_ACC_RDWR_F, h5file_id, h5error)
    if (h5error<debugflag) then
      write(*,*)  'h5error',       h5error,trim(h5filename),'h5file_id', h5file_id
    elseif (h5error<0)  then
      return(h5error)
    endif
      !dataset
      CALL h5dopen_f(h5file_id,   trim(h5datasetname), h5dataset_id, h5error)
      if (h5error<debugflag) then
        write(*,*)  'h5error',       h5error, trim(h5datasetname),'h5dataset_id', h5dataset_id
      elseif (h5error<0)  then
        return(h5error)
      endif
        ! dataspace
        call h5dget_space_f(h5dataset_id, h5dataspace_id,  h5error) 
        if (h5error<debugflag) then
          write(*,*)  'h5error',       h5error,'h5dataspace_id',h5dataspace_id
        elseif (h5error<0)  then
          return(h5error)
        endif
          ! rank and shape
          call h5sget_simple_extent_ndims_f(h5dataspace_id, h5rank, h5error) 
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5rank',h5rank, h5dims,h5maxdims
          elseif (h5error<0)  then
            return(h5error)
          endif
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1111
! rank=0 scalar
          if(h5rank==0) then
            h5rank=1
            allocate(h5dims(h5rank))
            allocate(h5maxdims(h5rank))
            h5maxdims(1)=1
            h5dims(1)=1
            h5datasize=1
            do i =1,h5rank
              h5datasize=h5datasize*h5dims(i)
            enddo
            allocate(h5dataset_data_integer(1))
            allocate(h5dataset_data_double(1))
            !allocate(gw_nq(1))
            call H5Dget_type_f(h5dataset_id, h5_file_datatype, h5error);
            if (h5error<debugflag) then
              write(*,*)  'h5error',       h5error,'h5_file_datatype',h5_file_datatype
            elseif (h5error<0)  then
              return(h5error)
            endif
!!!!!!!!!!!!!!!
!debug comment out ok
            ! datatype of memory data, test datatype
            call H5Tget_native_type_f(h5_file_datatype,H5T_DIR_ASCEND_F, h5_mem_datatype,h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5error',       h5error,'h5_mem_datatype',h5_mem_datatype
              elseif (h5error<0)  then
                return(h5error)
              endif
              call h5tequal_F(h5_mem_datatype,H5T_NATIVE_integer,h5flag,h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5error',       h5error,'h5_mem_datatype',h5_mem_datatype,'H5T_NATIVE_integer'
              elseif (h5error<0)  then
                return(h5error)
              endif
              call h5tequal_F(h5_file_datatype,H5T_NATIVE_integer,h5flag,h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5error',       h5error,'h5_file_datatype',h5_file_datatype,h5flag
              elseif (h5error<0)  then
                return(h5error)
              endif
!debug comment out ok
!!!!!!!!!!!!!!!

            call h5tequal_F(h5_file_datatype,H5T_NATIVE_integer,h5flag_integer,h5error)
            call h5tequal_F(h5_file_datatype,H5T_NATIVE_double,h5flag_double,h5error)
            if (h5flag_integer) then
              CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_integer(1), h5dims, h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5data',h5error,       h5dataset_Data_integer
              elseif (h5error<0)  then
                return(h5error)
              endif
            elseif (h5flag_double) then
              CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_double(1), h5dims, h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5data',h5error,       h5dataset_Data_double
              elseif (h5error<0)  then
                return(h5error)
              endif
            else
              write(*,*) 'h5 data type not supported'
            endif
            return(h5error)
          endif
! rank=0 scalar
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1111

          allocate(h5dims(h5rank))
          allocate(h5maxdims(h5rank))
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5rank'
          endif 
          call h5sget_simple_extent_dims_f(h5dataspace_id, h5dims, h5maxdims,h5error ) 
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error, 'h5dims', h5dims,'h5maxdims',h5maxdims
          elseif (h5error<0)  then
            return(h5error)
          endif
          h5datasize=1
          do i =1,h5rank
            h5datasize=h5datasize*h5dims(i)
          enddo
          allocate(h5dataset_data_double(h5datasize))
          allocate(h5dataset_data_integer(h5datasize))
        ! datatype of dataset
        call H5Dget_type_f(h5dataset_id, h5_file_datatype, h5error);
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5_file_datatype',h5_file_datatype
          elseif (h5error<0)  then
            return(h5error)
          endif
          ! datatype of memory data, test datatype
          call H5Tget_native_type_f(h5_file_datatype,H5T_DIR_ASCEND_F, h5_mem_datatype,h5error)
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5_mem_datatype',h5_mem_datatype
          elseif (h5error<0)  then
            return(h5error)
          endif
          call h5tequal_F(h5_mem_datatype,H5T_NATIVE_DOUBLE,h5flag,h5error)
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5_mem_datatype',h5_mem_datatype,h5flag
          elseif (h5error<0)  then
            return(h5error)
          endif
          call h5tequal_F(h5_file_datatype,H5T_NATIVE_DOUBLE,h5flag,h5error)
          if (h5error<debugflag) then
            write(*,*)  'h5error',       h5error,'h5_file_datatype',h5_file_datatype,h5flag
          elseif (h5error<0)  then
            return(h5error)
          endif
!!!!!!!!!!!!!!!!!!!!!!!!
!! read matrix old
!          call h5tequal_F(h5_file_datatype,H5T_NATIVE_integer,h5flag,h5error)
!          if (h5flag) then
!            CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_integer, h5dims, h5error)
!            if (h5error<debugflag) then
!              write(*,*)  'h5data',h5error,       h5dataset_Data_integer
!            elseif (h5error<0)  then
!              return(h5error)
!            endif
!          endif
!          call h5tequal_F(h5_file_datatype,H5T_NATIVE_double,h5flag,h5error)
!          if (h5flag) then
!            CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_double, h5dims, h5error)
!            if (h5error<debugflag) then
!              write(*,*)  'h5data',h5error,       h5dataset_Data_double
!            elseif (h5error<0)  then
!              return(h5error)
!            endif
!          endif
!! read matrix old
!!!!!!!!!!!!!!!!!!!!!!!!

!!!!!!!!!!!!!!!!!!!!!!!!
! read matrix 
            call h5tequal_F(h5_file_datatype,H5T_NATIVE_integer,h5flag_integer,h5error)
            call h5tequal_F(h5_file_datatype,H5T_NATIVE_double,h5flag_double,h5error)
            if (h5flag_integer) then
              CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_integer, h5dims, h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5data',h5error,       h5dataset_Data_integer
              elseif (h5error<0)  then
                return(h5error)
              endif
            elseif (h5flag_double) then
              CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_Data_double, h5dims, h5error)
              if (h5error<debugflag) then
                write(*,*)  'h5data',h5error,       h5dataset_Data_double
              elseif (h5error<0)  then
                return(h5error)
              endif
            else
              write(*,*) 'h5 data type not supported'
            endif
 
! read matrix 
!!!!!!!!!!!!!!!!!!!!!!!!


!        CALL h5dread_f(h5dataset_id,  h5_file_datatype, h5dataset_data, h5dims, h5error)
!        if (h5error<debugflag) then
!          write(*,*)  'h5error',       h5error
!        elseif (h5error<0)  then
!          return(h5error)
!        endif
      CALL h5dclose_f(h5dataset_id, h5error)
    CALL h5fclose_f(h5file_id, h5error)
  CALL h5close_f(h5error)
end subroutine h5gw_read


!IO
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    
! subroutine gw_eps_init(gw_ng_data ,gw_nmtx_max_data ,gw_nmtx_data ,gw_gind_eps2rho_data ,gw_gind_rho2eps_data ,gw_g_components_data ,gw_bvec_data ,gw_blat_data ,gw_qpts_data ,gw_nq_data ,gw_epsmat_diag_data ,gw_epsmat_full_data ,gw_q_g_commonsubset_indinrho ,gw_q_g_commonsubset_size)
 subroutine gw_eps_init(h5filename,gw_ng_data ,gw_nmtx_max_data ,gw_nmtx_data ,gw_gind_eps2rho_data ,gw_gind_rho2eps_data ,&
                                 gw_g_components_data ,gw_bvec_data ,gw_blat_data ,gw_qpts_data ,gw_nq_data ,&
              gw_epsmat_diag_data ,gw_epsmat_full_data ,gw_q_g_commonsubset_indinrho ,gw_q_g_commonsubset_size,gw_qabs)
    
          CHARACTER(LEN=256),intent (in) :: h5filename 
!gw_ng_data 
!gw_nmtx_max_data 
!gw_nmtx_data 
!gw_gind_eps2rho_data 
!gw_gind_rho2eps_data 
!gw_g_components_data 
!gw_bvec_data 
!gw_blat_data 
!gw_qpts_data 
!gw_nq_data 
!gw_epsmat_diag_data 
!gw_epsmat_full_data 
!gw_q_g_commonsubset_indinrho 
!gw_q_g_commonsubset_size



  !real(dp) ,dimension(:,:), intent (inout) :: gw_vcoul_data,gw_qpts_data
  !real(dp) ,allocatable, intent (inout) :: gw_vcoul_data(:,:),gw_qpts_data(:,:)
  real(dp) ,allocatable, intent (inout) :: gw_qpts_data(:,:)
!  real(dp) ,allocatable, intent (inout) :: gw_vcoul_data(:,:)
  real(dp), allocatable,intent (inout)  :: gw_blat_data(:),gw_bvec_data(:,:)
  integer, allocatable,intent (inout)  :: gw_gind_eps2rho_data(:,:), gw_gind_rho2eps_data(:,:),gw_nmtx_data(:)
   integer, allocatable,intent (inout)  :: gw_g_components_data(:,:)
   integer, allocatable  :: gw_grho_data(:),  gw_geps_data(:)
   !integer, allocatable,intent (inout)  :: gw_grho_data(:),  gw_geps_data(:),gw_g_components_data(:,:)
  integer, allocatable  :: gw_qgrid_data(:),gw_fftgrid_data(:)
  integer, allocatable ,intent (inout) :: gw_nq_data(:),gw_nmtx_max_data(:),gw_ng_data(:)
    
    integer(DP),allocatable ::gw_q_g_commonsubset_indinrhotmp1(:)
    real(DP),allocatable ,intent (inout) ::gw_qabs(:)
    INTEGER ,intent (inout) :: gw_q_g_commonsubset_size
    integer(DP),allocatable ,intent (inout) ::gw_q_g_commonsubset_indinrho(:)
  real(dp), allocatable ,intent (inout) :: gw_epsmat_full_data(:,:,:,:,:,:)

  real(dp), allocatable,intent (inout)  :: gw_epsmat_diag_data(:,:,:)



    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! CALL h5gn_members_f(file_id, "/mats", nmembers, error)
! write(*,*) "Number of root group member is " , nmembers
! do i = 0, nmembers - 1
!    CALL h5gget_obj_info_idx_f(file_id, "/mats", i, name_buffer, dtype, error)
! write(*,*) trim(name_buffer), dtype
! end do



    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! gweps read 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!!!!
! inverse alll dimensions for description
  h5datasetname='/mf_header/crystal/blat'              !f8 
  h5datasetname='/mf_header/crystal/bvec'              !f8 (3,3)

  h5datasetname='/mf_header/gspace/components'         !I4 (ng,3) G pts within cutoff
  h5datasetname='/mf_header/gspace/ng'                 !
  h5datasetname='/mf_header/gspace/FFTgrid'            !i4 (3)
  h5datasetname='/mf_header/gspace/ecutrho'            !
  h5datasetname='/eps_header/gspace/gind_eps2rho'      !i4 (nq,ng)
  h5datasetname='/eps_header/gspace/gind_rho2eps'      !i4 (nq,ng)
  h5datasetname='/eps_header/gspace/nmtx_max'          !i4 
  h5datasetname='/eps_header/gspace/nmtx'              !i4 (nq)  G pts for eps
                                                        
  h5datasetname='/eps_header/gspace/vcoul'             !f8 (nq,nmtx_max)
  h5datasetname='/eps_header/qpoints/nq'               !
  h5datasetname='/eps_header/qpoints/qpts'             !f8 (nq,3)
  h5datasetname='/eps_header/qpoints/qgrid'            !i4 (3)
                                                        
                                                        
  h5datasetname='/mats/matrix'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
  h5datasetname='/mats/matrix-diagonal'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
  !hdf5



h5datasetname='/mf_header/gspace/ng'      !i4 (nq,ng)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=1) then
 write(*,*)  'h5rank error(should be 1)',h5rank 
else
 h5dims1=h5dims
 allocate(gw_ng_data(h5dims1(1)))
 gw_ng_data=reshape(h5dataset_data_integer,h5dims1)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'ng()',gw_ng_data(:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif


h5datasetname='/eps_header/gspace/nmtx_max'      !i4 (nq,ng)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=1) then
 write(*,*)  'h5rank error(should be 1)',h5rank 
else
 h5dims1=h5dims
 allocate(gw_nmtx_max_data(h5dims1(1)))
 gw_nmtx_max_data=reshape(h5dataset_data_integer,h5dims1)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'nmtx_max()',gw_nmtx_max_data(:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif




h5datasetname='/eps_header/gspace/nmtx'      !i4 (nq,ng)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=1) then
 write(*,*)  'h5rank error(should be 1)',h5rank 
else
 h5dims1=h5dims
 allocate(gw_nmtx_data(h5dims1(1)))
 gw_nmtx_data=reshape(h5dataset_data_integer,h5dims1)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'nmtx()',gw_nmtx_data(:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif



h5datasetname='/eps_header/gspace/gind_eps2rho'      !i4 (nq,ng)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=2) then
 write(*,*)  'h5rank error(should be 2)',h5rank 
else
 h5dims2=h5dims
 allocate(gw_gind_eps2rho_data(h5dims2(1),h5dims2(2)))
 gw_gind_eps2rho_data=reshape(h5dataset_data_integer,h5dims2)
 write(*,*)  'shape h5dataset',shape(gw_gind_eps2rho_data)
 write(*,*)  'gw_gind_eps2rho_data()',gw_gind_eps2rho_data(1:100,1)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif


h5datasetname='/eps_header/gspace/gind_rho2eps'      !i4 (nq,ng)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=2) then
 write(*,*)  'h5rank error(should be 2)',h5rank 
else
 h5dims2=h5dims
 allocate(gw_gind_rho2eps_data(h5dims2(1),h5dims2(2)))
 gw_gind_rho2eps_data=reshape(h5dataset_data_integer,h5dims2)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'gw_gind_rho2eps_data()',gw_gind_rho2eps_data(1:100,1)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif




h5datasetname='/mf_header/gspace/components'               !
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=2) then
 write(*,*)  'h5rank error(should be 2)',h5rank 
else
 h5dims2=h5dims
 allocate(gw_g_components_data(h5dims2(1),h5dims2(2)))
 gw_g_components_data=reshape(h5dataset_data_integer,h5dims2)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'gw_g_components_data()',gw_g_components_data(:,1:7)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif



h5datasetname='/mf_header/crystal/bvec'               !
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=2) then
 write(*,*)  'h5rank error(should be 2)',h5rank 
else
 h5dims2=h5dims
 allocate(gw_bvec_data(h5dims2(1),h5dims2(2)))
 gw_bvec_data=reshape(h5dataset_data_double,h5dims2)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_double)
 write(*,*)  'gw_bvec_data()',gw_bvec_data(:,:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif



h5datasetname='/mf_header/crystal/blat'               !
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=1) then
 write(*,*)  'h5rank error(should be 1)',h5rank 
else
 h5dims1=h5dims
 allocate(gw_blat_data(h5dims1(1)))
 gw_blat_data=reshape(h5dataset_data_double,h5dims1)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_double)
 write(*,*)  'gw_blat_data()',gw_blat_data(:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif




h5datasetname='/eps_header/qpoints/qpts'               !
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=2) then
 write(*,*)  'h5rank error(should be 2)',h5rank 
else
 h5dims2=h5dims
 allocate(gw_qpts_data(h5dims2(1),h5dims2(2)))
 gw_qpts_data=reshape(h5dataset_data_double,h5dims2)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_double)
 write(*,*)  'gw_qpts_data()',gw_qpts_data(:,:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif



h5datasetname='/eps_header/qpoints/nq'               !
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=1) then
 write(*,*)  'h5rank error(should be 3)',h5rank 
else
          !      write(*,*) 'sizeof(int(i4b)):',sizeof(gw_nq)
!                write(*,*) 'sizeof(int(i8b)):',sizeof(gw_nqi8)
                write(*,*) 'sizeof(int):',sizeof(h5rank)
 h5dims1=h5dims
 allocate(gw_nq_data(h5dims1(1)))
 gw_nq_data=reshape(h5dataset_data_integer,h5dims1)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_integer)
 write(*,*)  'gw_nq_data()',gw_nq_data(:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif


h5datasetname='/mats/matrix-diagonal'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=3) then
 write(*,*)  'h5rank error(should be 3)',h5rank 
else
 h5dims3=h5dims
 allocate(gw_epsmat_diag_data(h5dims3(1),h5dims3(2),h5dims3(3)))
 gw_epsmat_diag_data=reshape(h5dataset_data_double,h5dims3)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_double)
 write(*,*)  'gw_epsmat_diag_data(:,1,1)',gw_epsmat_diag_data(:,1,:)
 deallocate(h5dims)
 deallocate(h5dataset_Data_integer)
 deallocate(h5dataset_Data_double)
endif

h5datasetname='/mats/matrix'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
call h5gw_read(h5filename,h5datasetname,h5dataset_data_double,h5dataset_Data_integer,h5dims,h5rank,h5error)
if (h5error<0)  write(*,*)  'h5error',h5error
if (h5rank/=6) then
 write(*,*)  'h5rank error(should be 6)',h5rank 
else
 h5dims6=h5dims
 write(*,*)  'hdims',h5dims 
 allocate(gw_epsmat_full_data(h5dims6(1),h5dims6(2),h5dims6(3),h5dims6(4),h5dims6(5),h5dims6(6)))
 gw_epsmat_full_data=reshape(h5dataset_data_double,h5dims6)
 write(*,*)  'shape h5dataset',shape(h5dataset_data_double)
 write(*,*)  'gw_epsmat_full_data(:,1,1)diag',gw_epsmat_full_data(:,1,1,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)diag',gw_epsmat_full_data(:,1,1,1,1,2)
 write(*,*)  'gw_epsmat_full_data(:,1,1)diag',gw_epsmat_full_data(:,1,1,1,1,3)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,1,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,2,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,3,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,4,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,5,1,1,1)
 write(*,*)  'gw_epsmat_full_data(:,1,1)wing',gw_epsmat_full_data(:,1,6,1,1,1)
endif


!!!!!!!!!!!!!!!!!!!
! prep read gw h5 data

! qabs
write(*,*) gw_bvec_data(:,1)
write(*,*) gw_bvec_data(:,2)
write(*,*) gw_bvec_data(:,3)
write(*,*) gw_qpts_data(:,1)
write(*,*) gw_qpts_data(:,2)
write(*,*) gw_qpts_data(:,3)

    allocate(gw_qabs(gw_nq_data(1)))
    do ig1 = 1, gw_nq_data(1)
      gw_qabs(ig1)=norm2(&
              gw_qpts_data(1,ig1)*gw_bvec_data(:,1)+ &
              gw_qpts_data(2,ig1)*gw_bvec_data(:,2)+ &
              gw_qpts_data(3,ig1)*gw_bvec_data(:,3))
!*gw_blat_data(1)

!write(*,*)              gw_qpts_data(1,ig1)*gw_bvec_data(1,:)
!write(*,*)              gw_qpts_data(2,ig1)*gw_bvec_data(2,:)
!write(*,*)              gw_qpts_data(3,ig1)*gw_bvec_data(3,:)


!debug
write(*,*)'gw_qabs debug ', gw_qabs(ig1),gw_epsmat_diag_data(:,1,ig1)
!debug
    enddo

!!!!!!!!!!!!!!
!  convert eps(q) g index to common gw-rho based g index
!     gw_q_g_commonsubset_size
!    gw_q_g_commonsubset2rho(:,:)
!    do ig = 1, gw_ng_data(1)
!      do iq=1,gw_nq_data(1)
!        gind_gw_eps=gw_gind_rho2eps_data(iq,ig)
!           if      (gind_gw_eps<gw_nmtx(iq))  then
!      enddo
!    enddo
!eps(gw_gind_rho2eps_data(iq,1:gw_nmtx_data(iq)))

allocate(gw_q_g_commonsubset_indinrho(gw_nmtx_max_data(1)))
gw_q_g_commonsubset_indinrho(:)=0
gw_q_g_commonsubset_indinrho(:)=gw_gind_eps2rho_data(1:gw_nmtx_data(1),1)

!write(*,*)  'gw_q_g_commonsubset_indinrho',gw_q_g_commonsubset_indinrho(1:10),shape(gw_q_g_commonsubset_indinrho)

do iq=1,gw_nq_data(1)
  do ig=1,gw_nmtx_max_data(1)
    if(gw_q_g_commonsubset_indinrho(ig)>0) then
      if (gw_gind_rho2eps_data(gw_q_g_commonsubset_indinrho(ig),iq)>gw_nmtx_data(iq) ) then
         gw_q_g_commonsubset_indinrho(ig)=0
       endif
    endif
  enddo
enddo
!write(*,*)  'gw_q_g_commonsubset_indinrho',gw_q_g_commonsubset_indinrho(:)
ig=0
  do ig1=1,gw_nmtx_max_data(1)
    if(gw_q_g_commonsubset_indinrho(ig1)>0) ig=ig+1
  enddo

write(*,*)  'gw_q_g_commonsubset_indinrho',gw_q_g_commonsubset_indinrho(:)
allocate(gw_q_g_commonsubset_indinrhotmp1(ig))
ig1=1
do ig=1,gw_nmtx_max_data(1)
  if(gw_q_g_commonsubset_indinrho(ig)>0) then 
!     write(*,*) gw_q_g_commonsubset_indinrhotmp1(ig1),gw_q_g_commonsubset_indinrho(ig)
     gw_q_g_commonsubset_indinrhotmp1(ig1)=gw_q_g_commonsubset_indinrho(ig) 
     ig1=ig1+1
  endif
enddo
deallocate(gw_q_g_commonsubset_indinrho)
allocate(gw_q_g_commonsubset_indinrho(size(gw_q_g_commonsubset_indinrhotmp1)))
gw_q_g_commonsubset_indinrho(:)=gw_q_g_commonsubset_indinrhotmp1(:) 

write(*,*)  'gw_q_g_commonsubset_indinrho',gw_q_g_commonsubset_indinrho(:),shape(gw_q_g_commonsubset_indinrho)
gw_q_g_commonsubset_size=size(gw_q_g_commonsubset_indinrho)
!  convert eps(q) g index to common gw-rho based g index
!!!!!!!!!!!!!


! prep read gw h5 data
!!!!!!!!!!!!!!!!!!!




!select case( h5rank)
!  case (1)
!h5dims3=h5dims
!allocate(gw_eps0mat_diag_data(h5dims3(1),h5dims3(2),h5dims3(3)))
!gw_eps0mat_diag_data=reshape(h5dataset_data,h5dims3)
!  case default
!  write(*,*) 'h5 read error'
!end select 


!!!!!!!!!!!!!!!!!!!!!!!
!!md5sum not working for non-text files
!    CALL md5_from_file('t.tgz',epsmatf_md5_cksum)
!    write (*,*) 'GW epsmat files:',trim(eps0mat_filename),'  MD5 sum:',epsmatf_md5_cksum
!    CALL md5_from_file('t1.tgz',epsmatf_md5_cksum)
!    write (*,*) 'GW epsmat files:',trim(eps0mat_filename),'  MD5 sum:',epsmatf_md5_cksum
!
!    CALL md5_from_file('eps0mat.10-epsilon_subsampling-cutoff10.h5',epsmatf_md5_cksum)
!    write (*,*) 'GW epsmat files:',trim(eps0mat_filename),'  MD5 sum:',epsmatf_md5_cksum
!    CALL md5_from_file(eps0mat_filename, epsmatf_md5_cksum)
!    write (*,*) 'GW epsmat files:',trim(eps0mat_filename),'  MD5 sum:',epsmatf_md5_cksum
!    CALL md5_from_file(epsmat_filename, epsmatf_md5_cksum)
!    write (*,*) 'GW epsmat files:',trim(epsmat_filename),'  MD5 sum:',epsmatf_md5_cksum
!!!!!!!!!!!!!!!!!!!!!!!

    !
    !!!!!! gweps read 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    
end subroutine gw_eps_init
    
 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!gw rho gind to psi gind
!write(*,*) 'gw'

subroutine get_gind_rhoandpsi_gw(gind_rho2psi_gw,gind_psi2rho_gw,gw_ng_data,&
gw_q_g_commonsubset_size,gvec_gw,gw_bvec_data,gw_q_g_commonsubset_indinrho)

    integer(DP),allocatable ,intent(inout)::gind_rho2psi_gw(:)
    integer(DP),allocatable ,intent(inout)::gind_psi2rho_gw(:)
    real(DP) ,intent(inout)::gvec_gw(3)
    real(DP) ,intent(inout)::gw_bvec_data(3,3)
  integer, allocatable ,intent (inout) :: gw_ng_data(:)
  integer, allocatable  :: gw_qgrid_data(:),gw_nq_data(:),gw_fftgrid_data(:),gw_nmtx_max_data(:)
    INTEGER ,intent(in) :: gw_q_g_commonsubset_size
    integer(DP),allocatable ,intent(in) ::gw_q_g_commonsubset_indinrho(:)
real(dp)::dgtmp
   integer, allocatable  :: gw_g_components_data(:,:)
   !integer, allocatable,intent (inout)  :: gw_g_components_data(:,:)

      allocate(gind_rho2psi_gw(gw_ng_data(1)))
      allocate(gind_psi2rho_gw(ngm))
!write(*,*) 'gw1'
      gind_rho2psi_gw(:)=0
      gind_psi2rho_gw(:)=0
         npw = ngk(ik)
      write(*,*)  gw_ng_data(1),ngm
      write(*,*)  gw_q_g_commonsubset_size,npwx,npw
      do ig1 = 1, gw_q_g_commonsubset_size
        do ig2=1,npw

          gvec_gw= gw_g_components_data(1,gw_q_g_commonsubset_indinrho(ig1))*gw_bvec_data(:,1)+ &
                   gw_g_components_data(2,gw_q_g_commonsubset_indinrho(ig1))*gw_bvec_data(:,2)+ &
                   gw_g_components_data(3,gw_q_g_commonsubset_indinrho(ig1))*gw_bvec_data(:,3)

          dgtmp=norm2(g(1:3,igk_k(ig2,ik0))-gvec_gw)
!write(*,*) 'gw2'
          if (dgtmp<machine_eps)then
      !      write(*,*) 'gw rho gind to psi gind: ig1,ig2', ig1, ig2,dgtmp,gvec_gw
      !      write(*,*) gw_g_components_data(:,ig1),g(1:3,igk_k(ig2,ik0)),gvec_gw
            write(*,*) 'gw rho gind to psi gind: ig1,ig2', ig1, ig2,dgtmp,gvec_gw
            write(*,*) 'ig2',ig2,ik0,igk_k(ig2,ik0),g(1:3,igk_k(ig2,ik0))
            gind_rho2psi_gw(ig1)=ig2
            gind_psi2rho_gw(ig2)=ig1
          endif
        enddo
      enddo

      write(*,*)  gw_ng_data(1),ngm

end subroutine get_gind_rhoandpsi_gw




    SUBROUTINE calcmdefect_all()! initialization and call M subroutines 

    write (*,*) 'enter calcmdefect module'

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !extra function: not fully implemented
    ALLOCATE (idx (ngm) )
    ALLOCATE (igtog (ngm) )
    ALLOCATE (gtoig (ngm) )
    idx(:) = 0
    igtog(:) = 0
    IF( lsda )THEN
       nbndup = nbnd
       nbnddown = nbnd
       nk = nks/2
       !     nspin = 2
    ELSE
       nbndup = nbnd
       nbnddown = 0
       nk = nks
       !     nspin = 1
    ENDIF


    DO ispin = 1, nspin
       DO ik = 1, nk
          ikk = ik + nk*(ispin-1)
          idx( igk_k(1:ngk(ikk),ikk) ) = 1
       ENDDO
    ENDDO

    ngtot_l = 0
    DO ig = 1, ngm
       IF( idx(ig) >= 1 )THEN
          ngtot_l = ngtot_l + 1
          igtog(ngtot_l) = ig
          gtoig(ig) = ngtot_l
       ENDIF
    ENDDO
    !extra function: not fully implemented
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


    ALLOCATE (aux(dfftp%nnr))
    ALLOCATE(auxr(dfftp%nnr))
    ALLOCATE(psiprod(dfftp%nnr))
    ALLOCATE(vgk(dfftp%nnr))
    ALLOCATE(vgk_perturb(dfftp%nnr))
    ALLOCATE( auxg( dfftp%ngm ) )
    !mltot=0
    !mnltot=0
    !mltot1=0
    !mltot2=0
    
    !write(*,*) 'use_calcmdefect', use_calcmdefect
    !
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! extra data read in, not used
    IF ( npool > 1 .or. nimage > 1 .or. nbgrp > 1 ) &
      CALL errore('calcmdefect', 'pool/band/image parallelization not (yet) implemented',1)
    IF ( noncolin .OR. lspinorb ) &
      CALL errore('calcmdefect', 'noncollinear/spinorbit magnetism not (yet) implemented',2)
    tmp_unit = find_free_unit()
    OPEN(unit=tmp_unit,file = 'calcmdefect.dat',status='old',err=20)
    !OPEN(unit=tmp_unit,file = trim(tmp_dir)//'calcmdefect.dat',status='old',err=20)
    20 continue
        READ(tmp_unit,calcmcontrol,iostat=ios)
    CLOSE(tmp_unit)
    ! extra data read in, not used
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! vloc.dat read
    iunpot_perturb=99 
    filpot_perturb=vperturb_filename
    !write(*,*) vperturb_filename
    open (unit = iunpot_perturb, file = filpot_perturb, form = 'formatted', &
         status = 'old', err = 99, iostat = ios_perturb)
    99 call errore ('mloc', 'opening file '//TRIM(filpot_perturb), abs (ios_perturb) )
    
    read (iunpot_perturb, '(a)') title_perturb
    read (iunpot_perturb, * ) nr1x_perturb, nr2x_perturb, nr3x_perturb,&
            nr1_perturb, nr2_perturb, nr3_perturb, nat_perturb, ntyp_perturb
    
    allocate(plot_perturb( nr1_perturb*nr2_perturb*nr3_perturb))
    allocate(ityp_perturb(nat_perturb))
    allocate(zv_perturb(ntyp_perturb))
    allocate(atm_perturb(ntyp_perturb))
    allocate(tau_perturb(3,nat_perturb))
    
    read (iunpot_perturb, * ) ibrav_perturb, celldm_perturb
    if (ibrav_perturb == 0) then
       do i_perturb = 1,3
          read ( iunpot_perturb, * ) ( at_perturb(ipol_perturb,i_perturb),ipol_perturb=1,3 )
       enddo
       alat_perturb=celldm_perturb(1)
    else
       call latgen(ibrav_perturb,celldm_perturb,at_perturb(1,1),at_perturb(1,2),at_perturb(1,3),omega_perturb)
       at_perturb(:,:)=at_perturb(:,:)/alat
    endif
    read (iunpot_perturb, * ) gcutm_perturb, dual_perturb, ecut_perturb, plot_num_perturb
    !read (iunpot_perturb, *) &
    read (iunpot_perturb, '(i4,3x,a2,3x,f5.2)') &
            (nt_perturb, atm_perturb(nt_perturb), zv_perturb(nt_perturb), nt_perturb=1, ntyp_perturb)
    read (iunpot_perturb, *) (ndum_perturb,  (tau_perturb (ipol_perturb, na_perturb), ipol_perturb = 1, 3), &
            ityp_perturb(na_perturb), na_perturb = 1, nat_perturb)
    read (iunpot_perturb, * ) (plot_perturb (ir_perturb), ir_perturb = 1, nr1_perturb * nr2_perturb * nr3_perturb)
    tau_perturb(:,:)=tau_perturb(:,:)*alat_perturb/alat

    !debug output
    !write (*,*) 'dv readin-vrs', sum(plot_perturb(:)-vrs(:,1))
    write (*,*) 'dv readin-vrs: , sum(plot_perturb(:)),sum(vrs(:,1)),sum(plot_perturb(:))-sum(vrs(:,1))'
    write (*,*)  sum(plot_perturb(:)),sum(vrs(:,1)),sum(plot_perturb(:))-sum(vrs(:,1))
    write (*,*) 'at-perturb', at_perturb
    write (*,*) 'alat-perturb', alat_perturb
    write (*,*) 'nr1_perturb ', nr1_perturb
    write (*,*) 'nr2_perturb ', nr2_perturb
    write (*,*) 'nr3_perturb ', nr3_perturb
    write (*,*) 'at', at(:,1)
    write (*,*) 'at', at(:,2)
    write (*,*) 'at', at(:,3)
    write (*,*) 'dfftp%nr1 ', dfftp%nr1
    write (*,*) 'dfftp%nr2 ', dfftp%nr2
    write (*,*) 'dfftp%nr3 ', dfftp%nr3
    write (*,*) 'dffts%nr1 ', dffts%nr1
    write (*,*) 'dffts%nr2 ', dffts%nr2
    write (*,*) 'dffts%nr3 ', dffts%nr3
    
     CALL md5_from_file(vperturb_filename, vf_md5_cksum)
    write (*,*) 'potential files:',TRIM(vperturb_filename),'  MD5 sum:',vf_md5_cksum
    !write (*,*) 'dv readin-vrs', plot_perturb(:)-vrs(:,1)
    !write (*,*) 'dv readin-vrs', vrs(:,1)
    !write (*,*) 'dv readin-vrs', plot_perturb(:)
    !
    !!!!!! vloc.dat read
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
     
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    

    
    allocate(evc3(npwx,nbnd))
    allocate(evc4(npwx,nbnd))
    allocate(mlat2(dfftp%nr3))
    allocate(mlat1(dfftp%nr3))
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! eps read 
    iunpot_perturb=99 
    filpot_perturb=eps_filename
    open (unit = iunpot_perturb, file = filpot_perturb, form = 'formatted', &
         status = 'old', err = 99, iostat = ios_perturb)
    
    
    read (iunpot_perturb, '(a)') title_perturb
!    read (iunpot_perturb, * ) k0screen_read
    read (iunpot_perturb, * ) nepslines
    
    allocate(eps_data(2,nepslines))
    do ig= 1, nepslines
         read (iunpot_perturb, * ) eps_data(1,ig),eps_data(2,ig)
    enddo
    write (*,*) 'eps lines  ', nepslines
    write (*,*) 'eps data  ', eps_data(1,1),eps_data(2,1)
    write (*,*) 'eps data  ', eps_data(1,2),eps_data(2,2)
    write (*,*) 'eps data  ', eps_data(1,3),eps_data(2,3)
    write (*,*) 'eps data  ', eps_data(1,7),eps_data(2,7)
    k0screen=k0screen_read
    
     CALL md5_from_file(eps_filename, epsf_md5_cksum)
    write (*,*) 'eps files:',trim(eps_filename),'  MD5 sum:',epsf_md5_cksum
    !write (*,*) 'dv readin-vrs', plot_perturb(:)-vrs(:,1)
    !write (*,*) 'dv readin-vrs', vrs(:,1)
    !write (*,*) 'dv readin-vrs', plot_perturb(:)
    !
    !!!!!! eps read 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   
 call gw_eps_init(epsmat_q0_filename,gw_ng_data_q0 ,gw_nmtx_max_data_q0 ,gw_nmtx_data_q0 ,&
gw_gind_eps2rho_data_q0 ,gw_gind_rho2eps_data_q0 ,&
                                 gw_g_components_data_q0 ,gw_bvec_data_q0 ,gw_blat_data_q0 ,gw_qpts_data_q0 ,gw_nq_data_q0 ,&
              gw_epsmat_diag_data_q0 ,gw_epsmat_full_data_q0 ,gw_q_g_commonsubset_indinrho_q0 ,&
gw_q_g_commonsubset_size_q0,gw_qabs_q0)

 call gw_eps_init(epsmat_q1_filename,gw_ng_data_q1 ,gw_nmtx_max_data_q1 ,gw_nmtx_data_q1 ,&
gw_gind_eps2rho_data_q1 ,gw_gind_rho2eps_data_q1 ,&
                                 gw_g_components_data_q1 ,gw_bvec_data_q1 ,gw_blat_data_q1 ,gw_qpts_data_q1 ,gw_nq_data_q1 ,&
              gw_epsmat_diag_data_q1 ,gw_epsmat_full_data_q1 ,gw_q_g_commonsubset_indinrho_q1 ,&
gw_q_g_commonsubset_size_q1,gw_qabs_q1)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


call get_gind_rhoandpsi_gw(gind_rho2psi_gw_q1,gind_psi2rho_gw_q1,gw_ng_data_q1,&
gw_q_g_commonsubset_size_q1,gvec_gw_q1,gw_bvec_data_q1,gw_q_g_commonsubset_indinrho_q1)
call get_gind_rhoandpsi_gw(gind_rho2psi_gw_q0,gind_psi2rho_gw_q0,gw_ng_data_q0,&
gw_q_g_commonsubset_size_q0,gvec_gw_q0,gw_bvec_data_q0,gw_q_g_commonsubset_indinrho_q0)

    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!eloc from rho*vloc
    mnl=0
    DO ig = 1, dffts%nnr
       mnl=mnl+rho%of_r(ig,1)
    ENDDO
    write(*,*) 'rhotot',mnl, ml/mnl*8
    
    ml=0
    auxr(:) =  vltot(:)
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*) 'el=rho*vltot', ml
    
    ml=0
    auxr(:) = v%of_r(:,1) 
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*) 'el=rho*v%of_r', ml
    
    ml=0
    auxr(:) = vrs(:,1)
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*) 'el=rho*vrs', ml
    !!!!!!!!!!!eloc from rho*vloc
    
    
    
    !allocate(evc1(size(evc)/nbnd,nbnd))
    !allocate(evc2(size(evc)/nbnd,nbnd))
    !write (*,*) 'npwx,npw',npwx,npw
    allocate(evc1(npwx,nbnd))
    allocate(evc2(npwx,nbnd))
    allocate(psic1(dfftp%nnr))
    allocate(psic2(dfftp%nnr))
    
       
    
    
!    tau_perturb(1,:)=tau_perturb(1,:)-(at(1,1)+at(2,1)+at(3,1))*1.4
!    tau_perturb(2,:)=tau_perturb(2,:)-(at(1,2)+at(2,2)+at(3,2))*1.4
!    tau(1,:)=tau(1,:)-(at(1,1)+at(2,1)+at(3,1))*1.0
!    tau(2,:)=tau(2,:)-(at(1,2)+at(2,2)+at(3,2))*1.0
!    do ig=1,nat_perturb
!    write (*,*) 'tau_perturb, ', shape(tau_perturb),tau_perturb(:,ig)
!    enddo

    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! loop through k points
    write (*,*) 'start M calculation k loop'
!    write (*,*) 'xk',xk,nk
    ibnd0=bnd_initial
    ibnd=bnd_final
    write (*,*) 'ibnd0->ibnd:',ibnd0,ibnd
    DO ik0=kpoint_initial,kpoint_final
     DO ik = 1, nk
      DO ispin = 1, nspin
        ikk = ik + nk*(ispin-1)
        ikk0 = ik0 + nk*(ispin-1)
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        !ml=0
        !write (*,*) 'evc read',ik
        
        !IF( nks > 1 ) CALL get_buffer (evc, nwordwfc, iunwfc, ik )
        !         write(*,*) 'npw,npwx,ngk(ik0),ngk(ikk)',npw,npwx,ngk(ik0),ngk(ikk)
        !npw = ngk(ik)
        !         write(*,*) 'npw,npwx,ngk(ik0),ngk(ikk)',npw,npwx,ngk(ik0),ngk(ikk)
        !            CALL init_us_2 (npw, igk_k(1,ik), xk (1, ik), vkb)
        !            CALL calbec ( npw, vkb, evc, becp )
        
        !write (*,*) 'evc2 read',ik
        !CALL get_buffer ( evc2, nwordwfc, iunwfc, ik )
        !write (*,*) 'evc1 read',ik0
        !CALL get_buffer ( evc1, nwordwfc, iunwfc, ik0 )
        !!!!!!!!!!!!write (*,*) "size evc evc1:" , size(evc),size(evc1)
        !!!!!!!!!!!!!!! evc
        
        
        !write(*,*) 'evc1', evc1(1:10,10)
        !write(*,*) 'evc2', evc2(1:10,10)
!    write (*,*) 'ik',ikk0,ikk
!    write(*,*) 'xk,xk0,xk-xk01',xk(1,ik),xk(1,ik0),xk(1,ik)-xk(1,ik0)
!    write(*,*) 'xk,xk0,xk-xk02',xk(2,ik),xk(2,ik0),xk(2,ik)-xk(2,ik0)
!    write(*,*) 'xk,xk0,xk-xk03',xk(3,ik),xk(3,ik0),xk(3,ik)-xk(3,ik0)
        CALL get_buffer ( evc2, nwordwfc, iunwfc, ikk )
        CALL get_buffer ( evc1, nwordwfc, iunwfc, ikk0 )
    
        if (calcmlocal) then
         call calcmdefect_ml_rs(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_ml_rd(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_ml_ks(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_ml_kd(ibnd0,ibnd,ikk0,ikk)
        endif
        if (calcmnonlocal) then
         call calcmdefect_mnl_ks(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_mnl_kd(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_mnl_rs(ibnd0,ibnd,ikk0,ikk)
         !call calcmdefect_mnl_rd(ibnd0,ibnd,ikk0,ikk)
        endif
        if (calcmcharge) then
         !call calcmdefect_charge(ibnd0,ibnd,ikk0,ikk)

         if (mcharge_dolfa) then
         call calcmdefect_charge_lfa(ibnd0,ibnd,ik0,ik)
         !!call calcmdefect_charge_2dlfa(ibnd0,ibnd,ikk0,ikk)
         !!call calcmdefect_charge_3dlfa(ibnd0,ibnd,ikk0,ikk)
         !!call calcmdefect_charge_qehlfa(ibnd0,ibnd,ikk0,ikk)
         else
         call calcmdefect_charge_nolfa(ibnd0,ibnd,ik0,ik)
         !!call calcmdefect_charge_2dnolfa(ibnd0,ibnd,ikk0,ikk)
         !!call calcmdefect_charge_3dnolfa(ibnd0,ibnd,ikk0,ikk)
         !!call calcmdefect_charge_qehnolfa(ibnd0,ibnd,ikk0,ikk)
         endif
        endif
    
    
      enddo
     enddo
    enddo
    
    END SUBROUTINE calcmdefect_all

    
    SUBROUTINE calcmdefect_noncolin()

      type(V_file) :: V_0, Bxc_1, Bxc_2, Bxc_3, V_p
      real(DP),allocatable ::  V_loc(:,:)

      write(*,"(//A/)") 'Enter calcmdefect_noncolin module '

!      write(*,*) eband
!      write(*,*) deband
!      write(*,*) demet
!      write(*,*) ewld
!      write(*,*) etxcc
!      write(*,*) etxc
!      write(*,*) ehart
!
!      ALLOCATE (idx (ngm) )
!      ALLOCATE (igtog (ngm) )
!      ALLOCATE (gtoig (ngm) )
!      idx(:) = 0
!      igtog(:) = 0
!      !IF( lsda )THEN
!       !  nbndup = nbnd
!       !  nbnddown = nbnd
!       !  nk = nks/2
!       !     nspin = 2
!      !ELSE
!       !  nbndup = nbnd
!       !  nbnddown = 0
!      nk = nks
!       !     nspin = 1
!      !ENDIF
!
!
!    
!      DO ik = 1, nk
!         ikk = ik
!         idx( igk_k(1:ngk(ikk),ikk) ) = 1
!      ENDDO
!   
!
!      ngtot_l = 0
!      DO ig = 1, ngm
!         IF( idx(ig) >= 1 )THEN
!            ngtot_l = ngtot_l + 1
!            igtog(ngtot_l) = ig
!            gtoig(ig) = ngtot_l
!         ENDIF
!      ENDDO
!
!
    ALLOCATE (aux(dfftp%nnr))
    ALLOCATE(auxr(dfftp%nnr))
    ALLOCATE(psiprod(dfftp%nnr))
    ALLOCATE(vgk(dfftp%nnr))
    ALLOCATE(vgk_perturb(dfftp%nnr))
    ALLOCATE( auxg( dfftp%ngm ) )
!
!      
!      OPEN(unit=tmp_unit,file = 'calcmdefect.dat',status='old',err=20)
!      20 continue
!         READ(tmp_unit,calcmcontrol,iostat=ios)
!      CLOSE(tmp_unit)
!      
      

      V_0%filename = V_0_filename
      Bxc_1%filename = Bxc_1_filename
      Bxc_2%filename = Bxc_2_filename
      Bxc_3%filename = Bxc_3_filename
      V_p%filename = V_p_filename

      call read_perturb_file(V_0)
     ! call read_perturb_file(Bxc_1)
     ! call read_perturb_file(Bxc_2)
      call read_perturb_file(Bxc_3)
      call read_perturb_file(V_p)
      
      allocate(V_loc ( V_0%nr1*V_0%nr2*V_0%nr3, 2))
      
      call get_vloc_colin(V_0, Bxc_3, V_loc)

      allocate(evc1(2*npwx,nbnd))
      allocate(evc2(2*npwx,nbnd))
      !allocate(evc3(2*npwx,nbnd))
      !allocate(evc4(2*npwx,nbnd))
      allocate(psic1(dfftp%nnr))
      allocate(psic2(dfftp%nnr))
      allocate(psic3(dfftp%nnr))
      allocate(psic4(dfftp%nnr))


      ! loop through k points
      write (*,"(/A/)") ' start M calculation k loop'
      ibnd0=bnd_initial
      ibnd=bnd_final
  !    do ibnd0 = bnd_initial, bnd_final
   !      ibnd=ibnd0
         DO ik0=kpoint_initial,kpoint_final
            DO ik = 1, nk
               
               ikk = ik 
               ikk0 = ik0 
         
               CALL get_buffer ( evc2, nwordwfc, iunwfc, ikk )
               CALL get_buffer ( evc1, nwordwfc, iunwfc, ikk0 )

            ! write(*,*) evc1(11:15, 27)/evc1(11+npwx:15+npwx, 27)
            ! write(*,*) evc1(11+npwx:15+npwx, 27)
            ! write(*,*) evc1(2*npwx-3:2*npwx+3, 27)
      
               if (calcmlocal) then
                  call calcmdefect_ml_rs_noncolin(ibnd0,ibnd,ikk0,ikk, V_0, V_loc)
               endif
               if (calcmnonlocal) then
                  call calcmdefect_mnl_ks_noncolin(ibnd0,ibnd,ikk0,ikk, V_0, V_p)
               endif

      1003 format(A24,I6,I6,A6,I6,I6 " ( ",e17.9," , ",e17.9," ) ",e17.9//)
   !  write (stdout,1003) 'M_tot ni ki --> nf kf ', ibnd0,ikk0, '-->', ibnd,ikk, mnl_d-mnl_p+ml_up+ml_down, abs(mnl_d-mnl_p+ml_up+ml_down)
      write (stdout,1003) 'M_tot ni ki --> nf kf ', ibnd0,ikk0, '-->', ibnd,ikk, mnl_d+ml_up+ml_down, abs(mnl_d+ml_up+ml_down)
            enddo
         enddo 
    ! enddo
    END SUBROUTINE calcmdefect_noncolin



   subroutine calcmdefect_soc()

      type(V_file) :: V_0, Bxc_1, Bxc_2, Bxc_3, V_p
      real(DP),allocatable ::  V_loc(:,:)
      complex(DP) :: ek, ek_tot
      integer  :: jj

      write(*,"(//A/)") 'Enter calcmdefect_soc module '

!      write(*,*) eband
!      write(*,*) deband
!      write(*,*) demet
!      write(*,*) ewld
!      write(*,*) etxcc
!      write(*,*) etxc
!      write(*,*) ehart
!
!      ALLOCATE (idx (ngm) )
!      ALLOCATE (igtog (ngm) )
!      ALLOCATE (gtoig (ngm) )
!      idx(:) = 0
!      igtog(:) = 0
!      !IF( lsda )THEN
!       !  nbndup = nbnd
!       !  nbnddown = nbnd
!       !  nk = nks/2
!       !     nspin = 2
!      !ELSE
!       !  nbndup = nbnd
!       !  nbnddown = 0
!      nk = nks
!       !     nspin = 1
!      !ENDIF
!
!
!    
!      DO ik = 1, nk
!         ikk = ik
!         idx( igk_k(1:ngk(ikk),ikk) ) = 1
!      ENDDO
!   
!
!      ngtot_l = 0
!      DO ig = 1, ngm
!         IF( idx(ig) >= 1 )THEN
!            ngtot_l = ngtot_l + 1
!            igtog(ngtot_l) = ig
!            gtoig(ig) = ngtot_l
!         ENDIF
!      ENDDO
!    !extra function: not fully implemented
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!
!      ALLOCATE (aux(dfftp%nnr))
!      ALLOCATE(auxr(dfftp%nnr))
!      ALLOCATE(psiprod(dfftp%nnr))
!      ALLOCATE(vgk(dfftp%nnr))
!      ALLOCATE(vgk_perturb(dfftp%nnr))
!      ALLOCATE( auxg( dfftp%ngm ) )
!
!
!      OPEN(unit=tmp_unit,file = 'calcmdefect.dat',status='old',err=20)
!      20 continue
!         READ(tmp_unit,calcmcontrol,iostat=ios)
!      CLOSE(tmp_unit)


      V_0%filename = V_0_filename
      Bxc_1%filename = Bxc_1_filename
      Bxc_2%filename = Bxc_2_filename
      Bxc_3%filename = Bxc_3_filename
      V_p%filename = V_p_filename

      call read_perturb_file(V_0)
     ! call read_perturb_file(Bxc_1)
     ! call read_perturb_file(Bxc_2)
      call read_perturb_file(Bxc_3)
      call read_perturb_file(V_p)

      allocate(V_loc ( V_0%nr1*V_0%nr2*V_0%nr3, 2))
      
      call get_vloc_colin(V_0, Bxc_3, V_loc)

      allocate(evc1(2*npwx,nbnd))
      allocate(evc2(2*npwx,nbnd))

      allocate(psic1(dfftp%nnr))
      allocate(psic2(dfftp%nnr))
      allocate(psic3(dfftp%nnr))
      allocate(psic4(dfftp%nnr))

      ! loop through k points
      write (*,"(/A/)") ' start M calculation k loop'
      ibnd0=bnd_initial
      ibnd=bnd_final
      
   !do ibnd0 = bnd_initial, bnd_final
   !   ibnd=ibnd0
      DO ik0=kpoint_initial,kpoint_final
         
         DO ik = 1, nk
            
            ikk = ik 
            ikk0 = ik0
            call g2_kin(ikk)
            !write(*,*) ik
            !write(*,*) g2kin
        
            CALL get_buffer ( evc2, nwordwfc, iunwfc, ikk )
            CALL get_buffer ( evc1, nwordwfc, iunwfc, ikk0 )

            !write(*,*) evc2(:,ibnd)
        !    ek = 0.d0
            
        !    do jj = 1, npwx
        !       ek = ek + conjg(evc2(jj,ibnd)) * evc2(jj,ibnd) *g2kin(jj) * wg(ibnd, ikk)&
        !          + conjg(evc2(jj+npwx,ibnd)) * evc2(jj+npwx,ibnd)*g2kin(jj)*wg(ibnd, ikk)
               !write(*,*) ek
        !    enddo
            
        !    ek_tot = ek_tot + ek
        !    write(*,*) 'E kinetic:' , ek
        !    write(*,*) 'E kinetic tot:' , ek_tot


            if (calcmlocal) then
               call calcmdefect_ml_rs_noncolin(ibnd0,ibnd,ikk0,ikk, V_0, V_loc)
            endif
            if (calcmnonlocal) then
               call calcmdefect_mnl_ks_soc(ibnd0,ibnd,ikk0,ikk, V_0, V_p)
            endif
      1003 format(A24,I6,I6,A6,I6,I6 " ( ",e17.9," , ",e17.9," ) ",e17.9//)
      !write (stdout,1003) 'M_tot ni ki --> nf kf ', ibnd0,ikk0, '-->', ibnd,ikk, mnl_d-mnl_p+ml_up+ml_down, abs(mnl_d-mnl_p+ml_up+ml_down)
      write (stdout,1003) 'M_tot ni ki --> nf kf ', ibnd0,ikk0, '-->', ibnd,ikk, mnl_d+ml_up+ml_down, abs(mnl_d+ml_up+ml_down)
         ENDDO
      ENDDO
   !enddo
   end subroutine calcmdefect_soc





    SUBROUTINE calcmdefect_ml_rd(ibnd0,ibnd,ik0,ik)
    !USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    INTEGER :: ibnd, ik, ik0,ibnd0
    auxr(:) =  vrs(:,1)
    ml=0
    mltot=0
    psic2(1:dffts%nnr) = (0.d0,0.d0)
    psic1(1:dffts%nnr) = (0.d0,0.d0)
    DO ig = 1, ngk(ik)
       psic2 (dffts%nl (igk_k(ig,ik) ) ) = evc2 (ig, ibnd)
    ENDDO
    DO ig = 1, ngk(ik0)
       psic1 (dffts%nl (igk_k(ig,ik0) ) ) = evc1 (ig, ibnd0)
    ENDDO
    !psicnorm=0
    !                 DO ig = 1, dffts%nnr
    !                     enl1=(log((psic1(ig))/psic2(ig)))
    !                   write(*,*) 'psi element product, ratio,', (enl1)
    !                 ENDDO
    psiprod(:)=psic1(:)
    CALL invfft ('Wave', psic2, dffts)
    CALL invfft ('Wave', psic1, dffts)
    
    !                 CALL fwfft ('Wave', psic1, dffts)
    !write(*,*) 'evc-ffpevc',sum(abs(psic1(:)-psiprod(:)))
    !write(*,*) 'evc',psiprod(:)
    !write(*,*) 'ffpevc',psic1(:)
    !                 CALL invfft ('Wave', psic1, dffts)
    
    !write(*,*) 'psic1', psic1(1:3)
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(1)))
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(2)))
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(3)))
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(4)))
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(5)))
    !write(*,*) 'pevc1:phases', AIMAG(LOG(psic1(6)))
    !write(*,*) at(:,1)
    !write(*,*) at(:,2)
    !write(*,*) at(:,3)
    !write(*,*) 't'
    !!write(*,*) 'arg',    2*3.141592653*(irx/dffts%nr1*at(1,1)+iry/dffts%nr2*at(1,2)+irz/dffts%nr3*at(1,3))*xk(1,ik)   
    !!write(*,*) 'arg',    2*3.141592653*(irx/dffts%nr1*at(2,1)+iry/dffts%nr2*at(2,2)+irz/dffts%nr3*at(2,3))*xk(2,ik)   
    !!write(*,*) 'arg',    2*3.141592653*(irx/dffts%nr1*at(3,1)+iry/dffts%nr2*at(3,2)+irz/dffts%nr3*at(3,3))*xk(3,ik)   
    !    CALL fft_index_to_3d (21, dffts, irx,iry,irz, offrange)
    !arg=2*3.141592653*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*xk(1,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*xk(2,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*xk(3,ik)   
    !write(*,*) 'ir', irx,iry,irz, arg
    !    CALL fft_index_to_3d (22, dffts, irx,iry,irz, offrange)
    !arg=2*3.141592653*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*xk(1,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*xk(2,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*xk(3,ik)   
    !write(*,*) 'ir', irx,iry,irz, arg
    !    CALL fft_index_to_3d (23, dffts, irx,iry,irz, offrange)
    !arg=2*3.141592653*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*xk(1,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*xk(2,ik) +&
    !    2*3.141592653*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*xk(3,ik)   
    !write(*,*) 'ir', irx,iry,irz, arg
    !
    !write(*,*) 'arg', (real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*xk(1,ik) 
    !write(*,*) 'arg', (real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*xk(2,ik) 
    !write(*,*) 'arg', (real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*xk(3,ik)   
    !write(*,*) 'pevc2:phases', AIMAG(LOG(psic2(1)))
    !write(*,*) 'pevc2:phases', AIMAG(LOG(psic2(2)))
    !write(*,*) 'pevc2:phases', AIMAG(LOG(psic2(3)))
    
    !write(*,*) 'psic1', psic1(1:2)
    !write(*,*) 'xk(ik)', xk(:,ik),ik
    !write(*,*) 'at', at
    !write(*,*) 'evcprod', mltot
    !mltot=0
    !psicnorm=0
    d1=((1.0/dffts%nr1*at(1,1))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr1*at(2,1))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr1*at(3,1))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d2=((1.0/dffts%nr2*at(1,2))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr2*at(2,2))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr2*at(3,2))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d3=((1.0/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    
    
    ml=0
    psicprod=0.0
    DO ig = 1, dffts%nnr
        CALL fft_index_to_3d (ig, dffts, irx,iry,irz, offrange)
    !write(*,*)'xyz,ig', irx,iry,irz,ig
    !write(*,*)'nrxyz', dffts%nr1,dffts%nr2,dffts%nr3
    !write(*,*)'k', xk(1:3,ik)
    ! write(*,*) 'arg x',   irx*2*3.141592653/dffts%nr1*xk(1,ik) 
    ! write(*,*) 'arg y',   iry*2*3.141592653/dffts%nr2*xk(2,ik) 
    ! write(*,*) 'arg z',   irz*2*3.141592653/dffts%nr3*xk(3,ik) 
    
    
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
    !!!!!!arg=(k-k0)*r
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
    arg=tpi*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
        tpi*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
        tpi*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0))   
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! shift arg center
    arg=irz*d3+(iry-iry/(dffts%nr2/2+1)*dffts%nr1)*d2+(irx-irx/(dffts%nr1/2+1)*dffts%nr1)*d1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


    !arg=-arg/alat
    !arg=irx*2*3.141592653/dffts%nr1*xk(1,ik) +&
    !    iry*2*3.141592653/dffts%nr2*xk(2,ik) +&
    !    irz*2*3.141592653/dffts%nr3*xk(3,ik) 
    !arg=-arg
    phase=CMPLX(COS(arg),SIN(arg),kind=dp)
    !phase=1
    !write (*,*) 'arg, phase', arg,phase
                          ml=ml+CONJG(psic1(ig))*psic2(ig)*auxr(ig)*phase
                          psicprod=psicprod+CONJG(psic1(ig))*psic2(ig)*phase
    !                     enl1=(log((psic1(ig))/psic2(ig)))
                      !if ((ik .eq. 2 .or. ik .eq.1 .or. ik.eq.14 ).and. ibnd .eq. 1) write(*,*) mltot, (enl1), arg, (arg-0.145)-(enl1)
    !                  if ((ik .eq. 4 .or. ik .eq.5 .or. ik.eq.14 ).and. ibnd .eq. 1) write(*,*) mltot
    !                   write(*,*) mltot, (enl1), arg, (arg-0.145)-(enl1)
    !                   write(*,*) 'psi element product, ratio, ikr, ratio-ikr:', (enl1), arg, (arg)-aimag(enl1)
    
    !                   write(*,*) 'psi ', psic1(ig),psic2(ig),psic1(ig)/psic2(ig),enl1
    !                  if ((ik .eq. 4 .or. ik .eq.5 .or. ik.eq.14 ).and. ibnd .eq. 1) write(*,*) mltot
    !psicnorm=psicnorm+CONJG(psic(ig))*psic(ig)
    !if (irz==dffts%nr3/2) then
    !write(*,*) 'psiplt ik',ik, 'xyz', irx,iry,irz,  'psi1', psic1(ig),abs( psic1(ig)),  'psi2', psic2(ig),abs(psic2(ig)),&
    !           'arg', arg,'prod', CONJG(psic1(ig))*psic2(ig)*phase, abs(CONJG(psic1(ig))*psic2(ig)*phase)
    !endif


    ENDDO
    ml=ml/dffts%nnr
    psicprod=psicprod/dffts%nnr
    write(*,*) 'psicprodd', psicprod , abs(psicprod)

    !mltot=0
                    !
    !                IF ( ibnd < ibnd_end ) THEN
    !                   !
    !                   ! ... two ffts at the same time
    !                   !
    !                   psic(dffts%nl(1:npw))  = evc(1:npw,ibnd) + &
    !                                           ( 0.D0, 1.D0 ) * evc(1:npw,ibnd+1)
    !                   psic(dffts%nlm(1:npw)) = CONJG( evc(1:npw,ibnd) - &
    !                                           ( 0.D0, 1.D0 ) * evc(1:npw,ibnd+1) )
    !                   !
    !                ELSE
    !                   !
    !                   psic(dffts%nl (1:npw))  = evc(1:npw,ibnd)
    !                   psic(dffts%nlm(1:npw)) = CONJG( evc(1:npw,ibnd) )
    !                   !
    !                END IF
                    !
                       !psic(dffts%nl(1:npw))  = evc(1:npw,ibnd) + &
    !              DO j = 1, dfftp%nnr
    !                  IF(gamma_only)THEN !.and.j>1)then
    !                     ml = ml +  conjg(psic(j,ibnd)) * evc(j,ibnd) * &
    !                                    auxg(j)
    !                  ELSE
    !                     ml = ml +  conjg(evc(j,ibnd)) * evc(j,ibnd) * &
    !                                    auxg(j)
    !                  ENDIF
    !               ENDDO
    !*wg(ibnd,ik)
    !if(ibnd .eq. 9) 
    !write (*,*) 'omega: ', omega
    !write (*,*) 'vrs-vofr ',  vrs(:,1)- v%of_r(:,1) - vltot(:)
    !arg=aimag(log(ml))
    mltot1=mltot1+ml*wg(ibnd,ik)!
    !write (stdout,*) 'ml: ik0, ik, ibnd0, ibnd: ', ik0, ik, ibnd0, ibnd, 'ml', ml , abs(ml),log(ml)!, arg, 'mltot', mltot1
    !write (stdout,*) 'modml original, ik0->ik:', ik0, ik, abs(ml)
    !write (stdout,*) 'psiprodphase original ', mltot
    !write (stdout,*) 'mltot ', mltot1
    write (*,*) 'mlrd ki->kf ',ik0,ik, ml, abs(ml)
    !arg=0
    !write (stdout,*) 'size evc auxg auxr: ', size(evc),size(auxg),size(auxr)
    !!!! Vl real space direct
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    END SUBROUTINE calcmdefect_ml_rd
     
    SUBROUTINE calcmdefect_ml_rs(ibnd0,ibnd,ik0,ik)
    USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    INTEGER :: ibnd, ik, ik0,ibnd0
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !ml=0
    
    !            IF( nks > 1 ) CALL get_buffer (evc, nwordwfc, iunwfc, ik )
    
    !     npw = ngk(ik)
    !            CALL init_us_2 (npw, igk_k(1,ik), xk (1, ik), vkb)
    !            CALL calbec ( npw, vkb, evc, becp )
    
    !        CALL get_buffer ( evc1, nwordwfc, iunwfc, ik0 )
    !        CALL get_buffer ( evc2, nwordwfc, iunwfc, ik )
    !!!!!!!!!!!!write (*,*) "size evc evc1:" , size(evc),size(evc1)
    !!!!!!!!!!!!!!! evc
    
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! vl in real super2prim, module
    auxr(:) =  vrs(:,1)
    psiprod(:)=0.00
    vgk_perturb(:)=0.00
    ml=0
    psicprod=0
    psicprod1=0
    !mltot=0
    !mltot1=0
    d1=((1.0/dffts%nr1*at(1,1))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr1*at(2,1))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr1*at(3,1))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d2=((1.0/dffts%nr2*at(1,2))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr2*at(2,2))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr2*at(3,2))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d3=((1.0/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    
    psic2(1:dffts%nnr) = (0.d0,0.d0)
    psic1(1:dffts%nnr) = (0.d0,0.d0)
    DO ig = 1, ngk(ikk)
       psic2 (dffts%nl (igk_k(ig,ikk) ) ) = evc2 (ig, ibnd)
    ENDDO
    DO ig = 1, ngk(ik0)
       psic1 (dffts%nl (igk_k(ig,ik0) ) ) = evc1 (ig, ibnd0)
    ENDDO
    CALL invfft ('Wave', psic2, dffts)
    CALL invfft ('Wave', psic1, dffts)
    
    
    
    !d1=((1.0/nr1_perturb*at_perturb(1,1))*(xk(1,ik)-xk(1,ik0)) +&
    !    (1.0/nr1_perturb*at_perturb(2,1))*(xk(2,ik)-xk(2,ik0)) +&
    !    (1.0/nr1_perturb*at_perturb(3,1))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    !d2=((1.0/nr2_perturb*at_perturb(1,2))*(xk(1,ik)-xk(1,ik0)) +&
    !    (1.0/nr2_perturb*at_perturb(2,2))*(xk(2,ik)-xk(2,ik0)) +&
    !    (1.0/nr2_perturb*at_perturb(3,2))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    !d3=((1.0/nr3_perturb*at_perturb(1,3))*(xk(1,ik)-xk(1,ik0)) +&
    !    (1.0/nr3_perturb*at_perturb(2,3))*(xk(2,ik)-xk(2,ik0)) +&
    !    (1.0/nr3_perturb*at_perturb(3,3))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    !
    arg=0
    inr=0
!    write(*,*) 'xk-xk01',xk(1,ik)-xk(1,ik0)
!    write(*,*) 'xk-xk02',xk(2,ik)-xk(2,ik0)
!    write(*,*) 'xk-xk03',xk(3,ik)-xk(3,ik0)
    do irz =0, nr3_perturb-1
    ir3mod=irz-(irz/(dffts%nr3))*dffts%nr3
    do iry =0, nr2_perturb-1
    ir2mod=iry-(iry/(dffts%nr2))*dffts%nr2
    do irx =0, nr1_perturb-1
    ir1mod=irx-(irx/(dffts%nr1))*dffts%nr1
    !arg=tpi*(real(irx)/nr1_perturb*at_perturb(1,1)+real(iry)/nr2_perturb*at_perturb(1,2)&
    !                                              +real(irz)/nr3_perturb*at_perturb(1,3))*(xk(1,ik)-xk(1,ik0)) +&
    !    tpi*(real(irx)/nr1_perturb*at_perturb(2,1)+real(iry)/nr2_perturb*at_perturb(2,2)&
    !                                              +real(irz)/nr3_perturb*at_perturb(2,3))*(xk(2,ik)-xk(2,ik0)) +&
    !    tpi*(real(irx)/nr1_perturb*at_perturb(3,1)+real(iry)/nr2_perturb*at_perturb(3,2)&
    !                                              +real(irz)/nr3_perturb*at_perturb(3,3))*(xk(3,ik)-xk(3,ik0))   
    
    arg=irz*d3+iry*d2+irx*d1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!
    !move vloc center 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!
    !arg=ir3mod*d3+ir2mod*d2+ir1mod*d1
    
    arg=tpi*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
        tpi*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
        tpi*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0))   
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! shift arg center
    arg=irz*d3+(iry-iry/(nr2_perturb/2+1)*nr2_perturb)*d2+(irx-irx/(nr1_perturb/2+1)*nr1_perturb)*d1
    !arg=irz*d3+(iry-iry/(dffts%nr2/2+1)*dffts%nr1)*d2+(irx-irx/(dffts%nr1/2+1)*dffts%nr1)*d1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !arg=irz*d3+iry*d2+irx*d1
    
    phase=CMPLX(COS(arg),SIN(arg),kind=dp)
    inr=inr+1
    irnmod=(ir3mod)*dffts%nr1*dffts%nr2+(ir2mod)*dffts%nr1+ir1mod+1
    ml=ml+CONJG(psic1(irnmod))*psic2(irnmod)*plot_perturb(inr)*phase
    psicprod=psicprod+CONJG(psic1(irnmod))*psic2(irnmod)*phase
    psicprod1=psicprod1+CONJG(psic1(irnmod))*psic2(irnmod)
    !ml2=ml2+CONJG(psic1(irnmod))*psic2(irnmod)*plot_perturb(inr)*phase
    !mltot=mltot+CONJG(psic1(irnmod))*psic2(irnmod)*phase
    !mltot1=mltot1+CONJG(psic1(irnmod))*psic2(irnmod)
    !write (*,*) 'iri',ir1mod,ir2mod,ir3mod
    !write (*,*) 'grid ', irnmod
    !write (*,*) 'psic1 ', psic1(irnmod)
    !write (*,*) 'psic2 ', psic2(irnmod)
    !write (*,*) 'arg', arg
    
    if ( irnmod<0 .or. irnmod>dffts%nnr ) then
       write (*,*) 'grid mismatch', irnmod, dffts%nnr 
    endif
    
    
    if (irz==dffts%nr3/2) then
            argt= atan2(real(CONJG(psic1(irnmod))*psic2(irnmod)*phase),aimag(CONJG(psic1(irnmod))*psic2(irnmod)*phase))
            argt2= atan2(real(CONJG(psic1(irnmod))*psic2(irnmod)),aimag(CONJG(psic1(irnmod))*psic2(irnmod)))
            if (argt<0) argt=argt+tpi
!            if (argt2<0) argt2=argt2+tpi
!    write(*,*) 'psiplts ik',ik, 'xyz', irx,iry,irz,  'psi1', psic1(irnmod),abs( psic1(irnmod)),  'psi2', &
!                        psic2(irnmod),abs(psic2(irnmod)),&
!   'arg', arg,'prod', CONJG(psic1(irnmod))*psic2(irnmod)*phase, abs(CONJG(psic1(irnmod))*psic2(irnmod)*phase),argt,argt2,&
!            real(CONJG(psic1(irnmod))*psic2(irnmod)),aimag(CONJG(psic1(irnmod))*psic2(irnmod)), psicprod1
    endif

       
    enddo
    enddo
    enddo
    
    !ml=ml/nr1_perturb/nr2_perturb/nr3_perturb
    ml=ml/dffts%nnr
    psicprod=psicprod/nr1_perturb/nr2_perturb/nr3_perturb
    psicprod1=psicprod1/nr1_perturb/nr2_perturb/nr3_perturb
    !psicprod=psicprod/dffts%nnr

!    write(*,*) 'psicprods', psicprod , abs(psicprod), abs(psicprod1)

    !write (*,*) 'ml super to primitive ki->kf',ik0,ik, ml, abs(ml), log(ml)
    !write (*,*) 'mlpsi*psi0 to primitive ki->kf',ik0,ik, mltot1, abs(mltot1), log(mltot1)
    !write (*,*) 'mlpsi*psi0*phase to primitive ki->kf',ik0,ik, mltot, abs(mltot), log(mltot)
    !write (*,*) 'modml super  ki->kf',ik0,ik, abs(ml)
    !write (*,*) 'Ml ki->kf ',ik0,ik, ml, abs(ml)
    write (*,1001) 'Ml ki->kf ',ik0,ik, xk(:,ik0),xk(:,ik), ml, abs(ml)
1001 format(A,I9,I9,3F14.9,3F14.9," ( ",e17.9," , ",e17.9," ) ",e17.9)
    !write(*,*) 'nrx_perturb',nr1_perturb,nr2_perturb,nr3_perturb
    !write(*,*) 'nrx_perturb',at,at_perturb, alat
    !write (*,*) 'dvgk', vgk(:)-vgk_perturb(:)
    !write (*,*) 'vgk', vgk(:)
    !write (*,*) 'vgk_perturb', vgk_perturb(:)
    !write (*,*) 'sum dvgk', sum(vgk(:)-vgk_perturb(:))
    !write(*,*) 'xk(ik)', xk(:,ik),ik
    !write(*,*) 'xk(ik0)', xk(:,ik0),ik0
    
    
    
    END SUBROUTINE calcmdefect_ml_rs

    SUBROUTINE calcmdefect_ml_kd(ibnd0,ibnd,ik0,ik)
    USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass

    INTEGER :: ibnd, ik, ik0,ibnd0
    ml=0
    psiprod(:)=0.00
    psicprod=0.00
    vgk(:)=0.00

    d1=((1.0/dffts%nr1*at(1,1))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr1*at(2,1))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr1*at(3,1))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d2=((1.0/dffts%nr2*at(1,2))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr2*at(2,2))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr2*at(3,2))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    d3=((1.0/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
        (1.0/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
        (1.0/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)) )*tpi 
    

    Do ig=1,ngm
      DO ig1 = 1, ngk(ik0)
        Do ig2=1, ngk(ik)
          if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))-g(:,ig)))<machine_eps) then
             psiprod(ig)=psiprod(ig)+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
          endif
        Enddo
      Enddo
   
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!psi=u*exp(i*k*x)
    !!!!!!!!!!!!!!!!!V_g=int V(r)*exp(-i*g*r)
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    phaseft=0.00
      Do inr=1,dffts%nnr
        CALL fft_index_to_3d (inr, dffts, irx,iry,irz, offrange)
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! shift arg center
        !iry=iry-iry/(dffts%nr2/2)*dffts%nr1
        !irx=irx-irx/(dffts%nr1/2)*dffts%nr1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        arg=((real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)-g(1,ig)) +&
             (real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)-g(2,ig)) +&
             (real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)-g(3,ig)))&
             *tpi 

    !arg=-arg
    !write(*,*)irx,iry,irz,inr
        phase=CMPLX(COS(arg),SIN(arg),kind=dp)
        vgk(ig)=vgk(ig)+auxr(inr)*phase
        phaseft=phaseft+phase
    !    if (arg>=0 .or. arg<=1) then
    !    else
    !    endif
        
      Enddo
    ml=ml+psiprod(ig)*vgk(ig)
    psicprod=psicprod+psiprod(ig)*phaseft
    Enddo
    ml=ml/dffts%nnr
    psicprod=psicprod/dffts%nnr
    write (*,*) 'mlkd ki->kf ',ik0,ik, ml, abs(ml)
    write (*,*) 'psicprodkd ',psicprod,abs(psicprod)
    END SUBROUTINE calcmdefect_ml_kd
     
    SUBROUTINE calcmdefect_ml_ks(ibnd0,ibnd,ik0,ik)
    USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    !      USE exx,    ONLY : exxenergy2, fock2
    !      USE funct,  ONLY : dft_is_hybrid
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! if uncomment, error message incompile: 
    !Error: The name ‘latgen’ at (1) has already been used as an external module name
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !use latgen, only: latgen
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    INTEGER :: ibnd, ik, ik0,ibnd0
    psiprod(:)=0.00
    vgk_perturb(:)=0.00
    !npw = ngk(ik)
    ml=0
    Do ig=1,ngm
      Do ig1=1,ngk(ik0)
        Do ig2=1,ngk(ik)
          if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))-g(:,ig)))<machine_eps) then
             psiprod(ig)=psiprod(ig)+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
          endif
        Enddo
      Enddo
    
      d1=((1.0/nr1_perturb*at_perturb(1,1))*(xk(1,ik)-xk(1,ik0)-g(1,ig)) +&
          (1.0/nr1_perturb*at_perturb(2,1))*(xk(2,ik)-xk(2,ik0)-g(2,ig)) +&
          (1.0/nr1_perturb*at_perturb(3,1))*(xk(3,ik)-xk(3,ik0)-g(3,ig)) )*tpi*alat_perturb/alat 

      d2=((1.0/nr2_perturb*at_perturb(1,2))*(xk(1,ik)-xk(1,ik0)-g(1,ig)) +&
          (1.0/nr2_perturb*at_perturb(2,2))*(xk(2,ik)-xk(2,ik0)-g(2,ig)) +&
          (1.0/nr2_perturb*at_perturb(3,2))*(xk(3,ik)-xk(3,ik0)-g(3,ig)) )*tpi*alat_perturb/alat 

      d3=((1.0/nr3_perturb*at_perturb(1,3))*(xk(1,ik)-xk(1,ik0)-g(1,ig)) +&
          (1.0/nr3_perturb*at_perturb(2,3))*(xk(2,ik)-xk(2,ik0)-g(2,ig)) +&
          (1.0/nr3_perturb*at_perturb(3,3))*(xk(3,ik)-xk(3,ik0)-g(3,ig)) )*tpi*alat_perturb/alat 
      
      arg=0
      inr=0
      do irz =0, nr3_perturb-1
      do iry =0, nr2_perturb-1
      do irx =0, nr1_perturb-1

!        arg=((real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)-g(1,ig)) +&
!             (real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)-g(2,ig)) +&
!             (real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)-g(3,ig)))&
!             *tpi 
 
          arg=irx*d1+iry*d2+irz*d3
          phase=CMPLX(COS(arg),SIN(arg),kind=dp)
          inr=inr+1

          vgk_perturb(ig)=vgk_perturb(ig)+plot_perturb(inr)*phase
       
      enddo
      enddo
      enddo
      
     
      ml=ml+psiprod(ig)*vgk_perturb(ig)
    enddo
    !ml=ml/nr1_perturb/nr2_perturb/nr3_perturb
    ml=ml/dffts%nnr
    write (*,*) 'mlks ki->kf ',ik0,ik, ml, abs(ml)
!    write (*,*) 'psicprodks ',psiprod(1),abs(psiprod(1))

    
    END SUBROUTINE calcmdefect_ml_ks
    

    SUBROUTINE calcmdefect_mnl_ks(ibnd0,ibnd,ik0,ik)
    !USE becmod, ONLY: becp,becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb, calbec, allocate_bec_type, deallocate_bec_type
    !USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    
    USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
    USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
    
    INTEGER :: ibnd, ik, ik0,ibnd0
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! initialization
    nkb_perturb=0


    DO nt_perturb = 1, ntyp_perturb
       DO na_perturb = 1, nat_perturb
          IF(ityp_perturb (na_perturb) == nt_perturb)THEN
              nkb_perturb = nkb_perturb + nh (nt_perturb)
          ENDIF
       ENDDO
    ENDDO
    
    
    CALL allocate_bec_type ( nkb, nbnd, becp )
    CALL allocate_bec_type ( nkb, nbnd, becp1 )
    CALL allocate_bec_type ( nkb, nbnd, becp2 )
    !write (*,*) '1 ', shape(vkb_perturb),'becp',shape(becp1%k),nkb,nbnd
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
    !write (*,*) '1 ', shape(vkb_perturb),'becp',shape(becp1_perturb%k),nkb_perturb,nbnd
    ALLOCATE(vkb_perturb(npwx,nkb_perturb))
    !        CALL open_buffer ( iuntmp, 'wfctemp', nwordwfc, io_level, exst )
    !do ik=1,nk
    !
    !        CALL get_buffer ( evc, nwordwfc, iunwfc, ik )
    !        CALL save_buffer ( evc, nwordwfc, iuntmp, ik )
    !write (*,*) "save" ,ik
    !enddo
    !        CALL close_buffer ( iuntmp, 'KEEP' )
    !        CALL open_buffer ( iuntmp, 'wfctemp', nwordwfc, io_level, exst )
    !call flush(iuntmp)
    !write (*,*) "size evc evc1:" , size(evc),size(evc1)
    !write (*,*) "s nnr:" , dffts%nnr
    !write (*,*) "p nnr:" , dfftp%nnr
    !write (*,*) "ngk(4):" ,  igk_k(4)
    !write (*,*) "ngk(14):" , igk_k(14)
    !write (*,*) "ngk(29):" , igk_k(29)
    
    !!!!!! initialization
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    
    
    !mnl=0
    
    !
    !            IF( nks > 1 ) CALL get_buffer (evc, nwordwfc, iunwfc, ik )
    
    !npw = ngk(ik)
    CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
    CALL calbec ( ngk(ik), vkb, evc, becp )
    
    !write (*,*) 'primitive', ngk(ik), igk_k(1,ik), xk (1, ik)
    !nat_perturb=1
                !CALL init_us_2 (ngk(ik), igk_k(1,ik0), xk (1, ik0), vkb)
    !write (*,*) 'shape(vkb_perturb) ', shape(vkb_perturb),'becp',shape(becp1_perturb)
    !write (*,*) 'nat_perturb ', shape(nat_perturb),nat_perturb
    !write (*,*) 'ityp_perturb, ', shape(ityp_perturb),ityp_perturb
    !write (*,*) 'tau_perturb, ', shape(tau_perturb),tau_perturb
    !write (*,*) 'nkb_perturb ', shape(nkb_perturb),nkb_perturb
    !write (*,*) '1 ', shape(vkb),'becp',shape(becp1_perturb)
    
    
    
    !npw = ngk(ik0)
    CALL init_us_2_perturb (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
    CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
    
    !write (*,*) '1 ', shape(vkb_perturb),shape(evc1),ngk(ik0),npwx
    !write (*,*) 'evc1 ', evc1
    !write (*,*) 'vkb ', vkb
    !write (*,*) '1 ', shape(vkb_perturb),shape(becp1_perturb)
    
    !npw = ngk(ik)
    CALL init_us_2_perturb (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
    CALL calbec ( ngk(ik), vkb_perturb, evc2, becp2_perturb )
    
    !write (*,*) 'becp1 ', shape(vkb),shape(becp1)
    !write (*,*) 'becp1 ', shape(vkb),shape(becp1)
    !write (*,*) '1 ', shape(vkb_perturb),shape(becp1_perturb)
    !write (*,*) 'evc2 ', evc2
    !write (*,*) 'vkb ', vkb
                !CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
    !evc1(:,:)=0.0
    !        CALL open_buffer ( iuntmp, 'wfctemp', nwordwfc, io_level, exst )
    !        CALL save_buffer ( evc, nwordwfc, iuntmp, ik0 )
    !        CALL get_buffer ( evc1, nwordwfc, iuntmp, ik0 )
    !write (*,*) 'evc1', evc1
    !write (*,*) 'evc ', evc
    !write (*,*) 'log evc1', log(evc1)
    !write (*,*) 'log evc ', log(evc)
    !write (*,*) 'igk_k ', igk_k(:,:)
    !write (*,*) 'igtog ', igtog(:)
    !write (*,*) 'gtoig ', gtoig(:)
    !write (*,*) 'tau ', tau
    
    !            CALL calbec ( ngk(ik0), vkb, evc1, becp1 )
    !            CALL calbec ( ngk(ik), vkb, evc2, becp2 )
    ijkb0 = 0
    !write (stdout,*) 'mnl: ',mnl
    mnl=0
    mnltot=0
    write (stdout,*) 'gamma_only:',gamma_only
    DO nt_perturb = 1, ntyp_perturb
       DO na_perturb = 1, nat_perturb
          !     arg=(xk(1,ik)*tau(1,na_perturb)+xk(2,ik)*tau(2,na_perturb)+xk(3,ik)*tau(3,na_perturb))*tpi/alat
          !     arg=arg-(xk(1,ik0)*tau(1,na_perturb)+xk(2,ik0)*tau(2,na_perturb)+xk(3,ik0)*tau(3,na_perturb))*tpi/alat
          !phase = CMPLX( COS(arg), -SIN(arg) ,KIND=DP)

          !phase = 1
          IF(ityp_perturb (na_perturb) == nt_perturb)THEN
             write (stdout,*) 'na: ',na_perturb,"nt:",nt_perturb,"nh:",nh(nt_perturb)
             write (stdout,*) 'dvan: ', dvan(:,:,nt_perturb)
             DO ih = 1, nh (nt_perturb)
                ikb = ijkb0 + ih
                IF(gamma_only)THEN
                   mnl=mnl+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                      * dvan(ih,ih,nt_perturb)
                ELSE
                   mnl=mnl+conjg(becp1_perturb%k(ikb,ibnd0))*becp2_perturb%k(ikb,ibnd) &
                      * dvan(ih,ih,nt_perturb)
                ENDIF
                write (stdout,*) 'mnl: ',mnl
                write (stdout,*) 'becp1: ',becp1_perturb%k(ikb,ibnd0)
                write (stdout,*) 'becp2: ',becp2_perturb%k(ikb,ibnd)
                write (stdout,*) 'dvan: ', dvan(ih,ih,nt_perturb)
                DO jh = ( ih + 1 ), nh(nt_perturb)
                   jkb = ijkb0 + jh
                   IF(gamma_only)THEN
                      mnl=mnl + &
                         (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                            becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                          * dvan(ih,jh,nt_perturb)
                   ELSE
                      mnl=mnl + &
                         (conjg(becp1_perturb%k(ikb,ibnd0))*becp2_perturb%k(jkb,ibnd)+&
                            conjg(becp1_perturb%k(jkb,ibnd0))*becp2_perturb%k(ikb,ibnd))&
                          * dvan(ih,jh,nt_perturb) !*phase
                   ENDIF
                   !write (stdout,*) 'mnl: ',mnl
!                write (stdout,*) 'mnl:ij ',mnl
!                write (stdout,*) 'becp1:i ',becp1_perturb%k(ikb,ibnd0)
!                write (stdout,*) 'becp2:i ',becp2_perturb%k(ikb,ibnd)
!                write (stdout,*) 'becp1:j ',becp1_perturb%k(jkb,ibnd0)
!                write (stdout,*) 'becp2:j ',becp2_perturb%k(jkb,ibnd)
!                write (stdout,*) 'dvan:ij ', dvan(ih,jh,nt_perturb)
 
    
                ENDDO
    
             ENDDO
             ijkb0 = ijkb0 + nh (nt_perturb)
          ENDIF
       ENDDO
    ENDDO
    mnltot=mnltot+mnl*wg(ibnd,ik)!
     
    CALL deallocate_bec_type (  becp )
    CALL deallocate_bec_type (  becp1 )
    CALL deallocate_bec_type (  becp2 )
    !write (*,*) '1 ', shape(vkb_perturb),'becp',shape(becp1%k),nkb,nbnd
    CALL deallocate_bec_type (  becp_perturb )
    CALL deallocate_bec_type (  becp1_perturb )
    CALL deallocate_bec_type (  becp2_perturb )
    !write (*,*) '1 ', shape(vkb_perturb),'becp',shape(becp1_perturb%k),nkb_perturb,nbnd
    DEALLOCATE(vkb_perturb)
    
    !mnl=mnl/nr1_perturb/nr2_perturb/nr3_perturb
    !if(ibnd .eq.9) 
    !write (stdout,*) 'ik0,ik,ibnd: super2primitive', ik0, ik, ibnd, 'mnl', mnl,'abs mnl', abs(mnl),'mnltot', mnltot
    !write (stdout,*) 'modmnl ik0,ik super2primitive', ik0,ik, abs(enl1)
    !write (stdout,*) 'Mnl ki->kf ', ik0,ik, mnl, abs(mnl)
    !write (stdout,*) 'Mnl ki->kf ', ik0,ik, xk(:,ik0),xk(:,ik), mnl, abs(mnl)

1001 format(A,I9,I9,3F14.9,3F14.9," ( ",e17.9," , ",e17.9," ) ",e17.9)
    write (stdout,1001) 'Mnl ki->kf ', ik0,ik, xk(:,ik0),xk(:,ik), mnl, abs(mnl)
    END SUBROUTINE calcmdefect_mnl_ks
    
    SUBROUTINE calcmdefect_mnl_kd(ibnd0,ibnd,ik0,ik)
    !USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
    USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
    INTEGER :: ibnd, ik, ik0,ibnd0
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! initialization
    nkb_perturb=0
    DO nt_perturb = 1, ntyp_perturb
       DO na_perturb = 1, nat_perturb
          IF(ityp_perturb (na_perturb) == nt_perturb)THEN
              nkb_perturb = nkb_perturb + nh (nt_perturb)
          ENDIF
       ENDDO
    ENDDO
    
    
    CALL allocate_bec_type ( nkb, nbnd, becp )
    CALL allocate_bec_type ( nkb, nbnd, becp1 )
    CALL allocate_bec_type ( nkb, nbnd, becp2 )
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
    CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
    
    ALLOCATE(vkb_perturb(npwx,nkb_perturb))
    !CALL open_buffer ( iuntmp, 'wfctemp', nwordwfc, io_level, exst )
    !do ik=1,nk
    !
    !CALL get_buffer ( evc, nwordwfc, iunwfc, ik )
    !CALL save_buffer ( evc, nwordwfc, iuntmp, ik )
    !write (*,*) "save" ,ik
    !enddo
    !CALL close_buffer ( iuntmp, 'KEEP' )
    !CALL open_buffer ( iuntmp, 'wfctemp', nwordwfc, io_level, exst )
    !!call flush(iuntmp)
    !write (*,*) "size evc evc1:" , size(evc),size(evc1)
    !write (*,*) "s nnr:" , dffts%nnr
    !write (*,*) "p nnr:" , dfftp%nnr
    !!write (*,*) "ngk(4):" ,  igk_k(4)
    !!write (*,*) "ngk(14):" , igk_k(14)
    !!write (*,*) "ngk(29):" , igk_k(29)
    !
    !!!!!!! initialization
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !
    !
    !
    !mnl=0
    !
    !
    !IF( nks > 1 ) CALL get_buffer (evc, nwordwfc, iunwfc, ik )
    !
    !npw = ngk(ik)
    !CALL init_us_2 (npw, igk_k(1,ik), xk (1, ik), vkb)
    !CALL calbec ( npw, vkb, evc, becp )
    
    
    
    
    
    
    enl1=0
    !npw = ngk(ik0)
    !CALL get_buffer ( evc1, nwordwfc, iuntmp, ik0 )
    !CALL get_buffer ( evc2, nwordwfc, iuntmp, ik )
    CALL init_us_2 (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb)
    CALL calbec ( ngk(ik0), vkb, evc1, becp1 )
    !npw = ngk(ik)
    CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
    CALL calbec ( ngk(ik), vkb, evc2, becp2 )
    ijkb0 = 0
    DO nt = 1, ntyp
       DO na = 1, nat
          !arg=(xk(1,ik)*tau(1,na)+xk(2,ik)*tau(2,na)+xk(3,ik)*tau(3,na))*tpi/alat
          !arg=arg-(xk(1,ik0)*tau(1,na)+xk(2,ik0)*tau(2,na)+xk(3,ik0)*tau(3,na))*tpi/alat
          !phase = CMPLX( COS(arg), -SIN(arg) ,KIND=DP)
          phase = 1
          IF(ityp (na) == nt)THEN
             DO ih = 1, nh (nt)
                ikb = ijkb0 + ih
                IF(gamma_only)THEN
                   enl1=enl1+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                      * dvan(ih,ih,nt)
                ELSE
                   enl1=enl1+conjg(becp1%k(ikb,ibnd0))*becp2%k(ikb,ibnd) &
                      * dvan(ih,ih,nt)
                ENDIF
                DO jh = ( ih + 1 ), nh(nt)
                   jkb = ijkb0 + jh
                   IF(gamma_only)THEN
                      enl1=enl1 + &
                         (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                            becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                          * dvan(ih,jh,nt)
                   ELSE
                      enl1=enl1 + &
                         (conjg(becp1%k(ikb,ibnd0))*becp2%k(jkb,ibnd)+&
                            conjg(becp1%k(jkb,ibnd0))*becp2%k(ikb,ibnd))&
                          * dvan(ih,jh,nt) *phase
                   ENDIF
    
                ENDDO
    
             ENDDO
             ijkb0 = ijkb0 + nh (nt)
          ENDIF
       ENDDO
    ENDDO
    mnltot=mnltot+enl1*wg(ibnd,ik)!
     
    CALL deallocate_bec_type (  becp )
    CALL deallocate_bec_type (  becp1 )
    CALL deallocate_bec_type (  becp2 )
    !write (*,*) '1 ', shape(vkb_perturb),'becp',shape(becp1%k),nkb,nbnd
    CALL deallocate_bec_type (  becp_perturb )
    CALL deallocate_bec_type (  becp1_perturb )
    CALL deallocate_bec_type (  becp2_perturb )
    DEALLOCATE(vkb_perturb)

    write(*,*)   'mnlkd ki->kf ',ik0,ik, enl1, abs(enl1)
    END SUBROUTINE calcmdefect_mnl_kd
    

    
!    SUBROUTINE calcmdefect_charge(ibnd0,ibnd,ik0,ik)
!    use splinelib, only: dosplineint,spline,splint
!    INTEGER :: ibnd, ik, ik0,ibnd0
!    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
!!    real(DP) , allocatable:: kmodvec(:)
!!    real(DP) , allocatable:: epskvec(:), eps_data1(:), eps_data2(:), eps_data_dy(:)
!    real(DP) , allocatable::  eps_data_dy(:)
!    real(DP) :: epsk
!!    allocate(eps_data1(size(eps_data(1,:))))
!!    allocate(eps_data2(size(eps_data(1,:))))
!    allocate(eps_data_dy(size(eps_data(1,:))))
!    
!    call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))
!
!    write (*,*) 'enter M charge calculation', ibnd, ik, ik0,ibnd0
!    k0screen=tpiba*0.01
!    psiprod(:)=0.00
!    vgk(:)=0.00
!    
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    !!!!!!!!!!!!!!!!!M=      1/(|xk_f-xk_i|)sum_G' u1^dagger(G')*u2(G')*N_Gz
!    mcharge0=0
!    icount=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!        if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
!           icount=icount+1
!           mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!        endif
!      Enddo
!    Enddo
!    deltak=((xk(1,ik)-xk(1,ik0))**2&
!           +(xk(2,ik)-xk(2,ik0))**2)**0.5*tpiba
!    
!    mcharge2=mcharge0*tpi/(deltak**2+k0screen**2)**0.5
!    mcharge1=mcharge0*tpi/deltak
!    !mcharge1=mcharge1/dffts%nr1/dffts%nr2/dffts%nr3/dffts%nr3
!    !mcharge2=mcharge2/dffts%nr1/dffts%nr2/dffts%nr3/dffts%nr3
!    mcharge1=mcharge1/dffts%nnr
!    mcharge2=mcharge2/dffts%nnr
!    write(*,*)   'Mcharge2DLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1), icount
!    write(*,*)   'Mcharge2DLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2), icount
!    write(*,*)   'mcharge0 deltak', mcharge0,deltak
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    mcharge1=0
!    mcharge2=0.00
!    icount=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!           mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!           icount=icount+1
!           deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
!                      -g(1:2,igk_k(ig2,ik))&
!                      +xk(1:2,ik0)-xk(1:2,ik))*tpiba
!           mcharge1=mcharge1+mcharge0*tpi/deltakG
!           mcharge2=mcharge2+mcharge0*tpi/(deltakG**2+k0screen**2)**0.5
!      Enddo
!    Enddo
!    mcharge1=mcharge1/dffts%nnr
!    mcharge2=mcharge2/dffts%nnr
!    write(*,*)  'Mcharge2DnoLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1),icount
!    write(*,*)  'Mcharge2DnoLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2),icount
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    Nlzcutoff=dffts%nr3/2
!    lzcutoff=Nlzcutoff*alat/dffts%nr1
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    mcharge1=0
!    mcharge2=0
!    mcharge3=0
!    mcharge4=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!    
!             mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!             deltakG=norm2(g(:,igk_k(ig1,ik0))&
!                        -g(:,igk_k(ig2,ik))&
!                        +xk(:,ik0)-xk(:,ik))*tpiba
!    
!             qxy=norm2(g(1:2,igk_k(ig1,ik0))&
!                        -g(1:2,igk_k(ig2,ik))&
!                        +xk(1:2,ik0)-xk(1:2,ik))*tpiba
!    
!             qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
!                  xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
!    !         if (norm2(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik)))<eps) then
!                 mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)
!                 mcharge2=mcharge2+mcharge0*4*pi/(deltakG**2+k0screen**2)
!                 mcharge3=mcharge3+mcharge0*4*pi/(deltakG**2)&
!                   *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
!                 mcharge4=mcharge4+mcharge0*4*pi/(deltakG**2+k0screen**2)&
!                   *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
!    !         endif
!      Enddo
!    Enddo
!    mcharge1=mcharge1/dffts%nnr
!    mcharge2=mcharge2/dffts%nnr
!    mcharge3=mcharge3/dffts%nnr
!    mcharge4=mcharge4/dffts%nnr
!    write(*,*)  'Mcharge3DnoLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
!    write(*,*)  'Mcharge3DnoLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2)
!    write(*,*)  'Mcharge3DcutnoLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
!    write(*,*)  'Mcharge3DcutnoLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4)
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    mcharge0=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!        if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<eps) then
!             mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!        endif
!      Enddo
!    Enddo
!    deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
!    qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
!    qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
!    mcharge1=mcharge0*2*pi/(deltak**2)
!    mcharge2=mcharge0*4*pi/(deltak**2+k0screen**2)
!    mcharge3=mcharge0*4*pi/(deltak**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
!    mcharge4=mcharge0*4*pi/(deltak**2+k0screen**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
!     
!    mcharge1=mcharge1/dffts%nnr
!    mcharge2=mcharge2/dffts%nnr
!    mcharge3=mcharge3/dffts%nnr
!    mcharge4=mcharge4/dffts%nnr
!    write(*,*)  'Mcharge3DLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
!    write(*,*)  'Mcharge3DLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2)
!    write(*,*)  'Mcharge3DcutLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
!    write(*,*)  'Mcharge3DcutLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4)
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!     
!    mcharge0=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!        if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
!             mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!         
!        endif
!      Enddo
!    Enddo
!
!    deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
!    !allocate(kmodvec(1))
!    !kmodvec(1)=deltak
!    !allocate(epskvec(1))
!    !call dosplineint(eps_data(1,:),eps_data(2,:),kmodvec(:),epskvec(:))
!    epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltak)
!             if (deltak>0.2) then
!                    epsk=0.0
!             endif
!
!!    write (*,*) 'epsklfa', deltak,epsk
!
!    mcharge1=mcharge0*tpi/deltak*epsk
!    mcharge1=mcharge1/dffts%nnr
!    write(*,*)  'Mcharge2DLFAes ki->kf'   ,ik0,ik,   mcharge1, abs(mcharge1)
!
!    !deallocate(epskvec)
!    !deallocate(kmodvec)
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    
!    mcharge0=0
!    mcharge1=0
!    DO ig1 = 1, ngk(ik0)
!      Do ig2=1,npw
!
!             deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
!                      -g(1:2,igk_k(ig2,ik))&
!                      +xk(1:2,ik0)-xk(1:2,ik))*tpiba
!             epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
!             if (deltakG>0.2) then
!                    epsk=0.0
!             endif
!             mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!             mcharge1=mcharge1+mcharge0*tpi/deltakG*epsk
!!    write (*,*) 'epsknolfa', deltakG,epsk
!         
!      Enddo
!    Enddo
!
!    !allocate(kmodvec(1))
!    !kmodvec(1)=deltak
!    !allocate(epskvec(1))
!    !call dosplineint(eps_data(1,:),eps_data(2,:),kmodvec(:),epskvec(:))
!
!    mcharge1=mcharge1/dffts%nnr
!    write(*,*)  'Mcharge2DnoLFAes ki->kf'   ,ik0,ik,   mcharge1, abs(mcharge1)
!
!    !deallocate(epskvec)
!    !deallocate(kmodvec)
!
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    !!!! epsk can;t be used in 3D error
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!    !   
!    !mcharge0=0
!    !mcharge1=0
!    !mcharge2=0
!    !DO ig1 = 1, ngk(ik0)
!    !  Do ig2=1,npw
!    !
!    !    mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
!    !    deltakG=norm2(g(:,igk_k(ig1,ik0))&
!    !               -g(:,igk_k(ig2,ik))&
!    !               +xk(:,ik0)-xk(:,ik))*tpiba
!    !
!    !    qxy=norm2(g(1:2,igk_k(ig1,ik0))&
!    !               -g(1:2,igk_k(ig2,ik))&
!    !               +xk(1:2,ik0)-xk(1:2,ik))*tpiba
!    !    qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
!    !         xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
!    !    !if (norm2(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik)))<eps) then
!
!    !    !allocate(kmodvec(1))
!    !    !kmodvec(1)=deltakG
!    !    !allocate(epskvec(1))
!    !    !eps_data1(:)=eps_data(1,:)
!    !    !eps_data2(:)=eps_data(2,:)
!    !    !call dosplineint(eps_data(1,:),eps_data(2,:),kmodvec(:),epskvec(:))
!    !    !call dosplineint(eps_data1,eps_data2,kmodvec,epskvec)
!    !    epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
!
!    !    mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)*epsk
!    !    mcharge2=mcharge3+mcharge0*4*pi/(deltakG**2)*epsk&
!    !      *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
!    !    !deallocate(epskvec)
!    !    !deallocate(kmodvec)
!    !    !endif
! 
!    !  Enddo
!    !Enddo
!    !
!    !mcharge1=mcharge1/dffts%nnr
!    !mcharge2=mcharge2/dffts%nnr
!    !write(*,*)  'Mcharge3DcutnoLFAes ki->kf',ik0,ik,   mcharge1, abs(mcharge1)
!    !write(*,*)  'Mcharge3DnoLFAes ki->kf'   ,ik0,ik,   mcharge2, abs(mcharge2)
!    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!    END SUBROUTINE calcmdefect_charge
      
    SUBROUTINE calcmdefect_charge_lfa(ibnd0,ibnd,ik0,ik)
    use splinelib, only: dosplineint,spline,splint
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4,mcharge5,mcharge6
    INTEGER :: ibnd, ik, ik0,ibnd0
    real(DP) , allocatable::  eps_data_dy(:)
    real(DP) :: epsk, deltak_para,q2d_coeff
    !k0screen=tpiba*0.01
    allocate(eps_data_dy(size(eps_data(1,:))))
    call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))

    !k0screen=tpiba*0.01
    mcharge0=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1, ngk(ik)
        if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<machine_eps) then
             mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
        endif
      Enddo
    Enddo
    deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    deltak_para=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltak_para)
    if (deltak>maxval(eps_data(1,:)))      epsk=minval(eps_data(2,:))

    qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
    q2d_coeff= (1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    mcharge1=mcharge0*4*pi/(deltak**2)
    mcharge2=mcharge0*4*pi/(deltak**2+k0screen**2)
    mcharge3=mcharge0*4*pi/(deltak**2)*epsk
    mcharge4=mcharge0*4*pi/(deltak**2)*            q2d_coeff!(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    mcharge5=mcharge0*4*pi/(deltak**2+k0screen**2)*q2d_coeff!(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    mcharge6=mcharge0*4*pi/(deltak**2)*epsk*       q2d_coeff!(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
     
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    mcharge4=mcharge4/dffts%nnr
    mcharge5=mcharge5/dffts%nnr
    mcharge6=mcharge6/dffts%nnr
    write(*,*)  'mcharge0           ki->kf ',ik0,ik,    mcharge0, abs(mcharge0)
    write(*,*)  'Mcharge3DLFAns     ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    write(*,*)  'Mcharge3DLFAs      ki->kf ',ik0,ik,    mcharge2, abs(mcharge2) , 'k0screen', k0screen
    write(*,*)  'Mcharge3DLFAes     ki->kf ',ik0,ik,    mcharge3, abs(mcharge3) , 'epsk',epsk 
    write(*,*)  'Mcharge3DcutLFAns  ki->kf ',ik0,ik,    mcharge4, abs(mcharge4)
    write(*,*)  'Mcharge3DcutLFAs   ki->kf ',ik0,ik,    mcharge5, abs(mcharge5) , 'k0screen', k0screen
    write(*,*)  'Mcharge3DcutLFAes  ki->kf ',ik0,ik,    mcharge6, abs(mcharge6) , 'epsk',epsk
     
    mcharge0=0
    icount=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1, ngk(ik)
        if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<machine_eps) then
           icount=icount+1
           mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
        endif
      Enddo
    Enddo
    deltak=((xk(1,ik)-xk(1,ik0))**2&
           +(xk(2,ik)-xk(2,ik0))**2)**0.5*tpiba
    
    mcharge1=mcharge0*tpi/deltak
    mcharge2=mcharge0*tpi/(deltak**2+k0screen**2)**0.5
    mcharge3=mcharge0*tpi/(deltak**2)**0.5*epsk
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    write(*,*)   'mcharge0       0ki->kf ',ik0,ik, mcharge0, abs(mcharge0)
    write(*,*)   'Mcharge2DLFAns 0ki->kf ',ik0,ik, mcharge1, abs(mcharge1)
    write(*,*)   'Mcharge2DLFAs  0ki->kf ',ik0,ik, mcharge2, abs(mcharge2) , 'k0screen', k0screen
    write(*,*)   'Mcharge2DLFAes 0ki->kf ',ik0,ik, mcharge3, abs(mcharge3) , 'epsk', epsk
 
     
 
    


    END SUBROUTINE calcmdefect_charge_lfa
 
    !SUBROUTINE calcmdefect_charge_2dlfa(ibnd0,ibnd,ik0,ik)
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !!write (*,*) 'enter M charge calculation', ibnd, ik, ik0,ibnd0
    !!k0screen=tpiba*0.01
    !
    !mcharge0=0
    !icount=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !    if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
    !       icount=icount+1
    !       mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !    endif
    !  Enddo
    !Enddo
    !deltak=((xk(1,ik)-xk(1,ik0))**2&
    !       +(xk(2,ik)-xk(2,ik0))**2)**0.5*tpiba
    !
    !mcharge1=mcharge0*tpi/deltak
    !mcharge2=mcharge0*tpi/(deltak**2+k0screen**2)**0.5
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
    !write(*,*)   'mcharge0 ki->kf ',ik0,ik, mcharge0, abs(mcharge0)
    !write(*,*)   'Mcharge2DLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1)
    !write(*,*)   'Mcharge2DLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2) , 'k0screen', k0screen
    !END SUBROUTINE calcmdefect_charge_2dlfa
    

 
    SUBROUTINE calcmdefect_charge_nolfa(ibnd0,ibnd,ik0,ik)
    use splinelib, only: dosplineint,spline,splint
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4,mcharge5,mcharge6
    INTEGER :: ibnd, ik, ik0,ibnd0
    real(DP) , allocatable::  eps_data_dy(:)
    real(DP) :: epsk, deltakG_para,q2d_coeff
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!GW
!|M|=int  u1(r) u2(r) [int eps(r,r')V(r')]
!   =int  u1(G')u2(G'+G) V(q+G)
!                        V(q+G)=int eps(q,G,G')V(q+G')
!GW
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    COMPLEX(DP),allocatable ::w_gw(:)
    real(DP),allocatable ::epsint_q1_tmp1(:)
    real(DP),allocatable ::epsint_q1_tmp2(:)
    real(DP),allocatable ::epsint_q1_tmp3(:)
    real(DP),allocatable ::epsint_q1_tmp4(:)
    real(DP),allocatable ::epsint_q0_tmp1(:)
    real(DP),allocatable ::epsint_q0_tmp2(:)
    real(DP),allocatable ::epsint_q0_tmp3(:)
    real(DP),allocatable ::epsint_q0_tmp4(:)
    real(DP),allocatable ::w1(:)
    real(DP) ::epsinttmp1s
    real(DP) ::epsinttmp2s
    real(DP) ::epsinttmp3s
    real(DP) ::epsinttmp4s
    complex(DP),allocatable ::epsmat_inted(:,:) ! interpolated eps matrix
    COMPLEX(DP) :: epstmp1,epstmp2
    INTEGER :: iq1,iq2,nqgrid_gw=48!fixme
!    INTEGER :: gw_ng
    INTEGER :: gind_gw_eps1,gind_gw_eps2
    INTEGER :: gind_psi1,gind_psi2
    INTEGER :: gind_gwrho1,gind_gwrho2
real(dp)::q1(3)
logical:: interpolate_2d,interpolate_smallq1d=.false.

    INTEGER :: gw_q_g_commonsubset_size
    COMPLEX(DP) ::  mcharge0gw,mcharge1gw,mcharge2gw,mcharge3gw,mcharge4gw,mcharge5gw,mcharge6gw

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! get interpolated eps matrix
! eps(0,0) fine after check
    icount=0
    allocate(epsint_q0_tmp1(gw_nq_data_q0(1)))
    allocate(epsint_q0_tmp2(gw_nq_data_q0(1)))
    allocate(epsint_q0_tmp3(gw_nq_data_q0(1)))
    allocate(epsint_q0_tmp4(gw_nq_data_q0(1)))


    allocate(epsmat_inted(gw_q_g_commonsubset_size,gw_q_g_commonsubset_size))
    epsmat_inted(:,:)=0.0
    

interpolate_2d=.false.
interpolate_smallq1d=.false.
       if(abs(norm2((xk(1:3,ik0)-xk(1:3,ik))*tpiba))<tpiba*(2*3**.5/3.0)*2.0/nqgrid_gw) then
             interpolate_smallq1d=.true.
       else
             interpolate_2d=.true.
       endif

if(interpolate_2d) then
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! 2d simple interpolate prepare fixme
    deltakG=norm2(xk(1:3,ik0)-xk(1:3,ik))*tpiba
             deltakG_para=deltakG
    allocate(w1(gw_nq_data_q1(1)))
    w1(:)=0.0
    do iq1 = 1, gw_nq_data_q1(1)
        q1(:)=   gw_qpts_data_q1(1,iq1)*gw_bvec_data_q1(:,1)+ &
              gw_qpts_data_q1(2,iq1)*gw_bvec_data_q1(:,2)+ &
              gw_qpts_data_q1(3,iq1)*gw_bvec_data_q1(:,3)
       if(abs(norm2((xk(1:3,ik0)-xk(1:3,ik))*tpiba)-norm2(q1(:)))<tpiba*(2*3**.5/3.0)*1.0/nqgrid_gw) then
         w1(iq1)=1/abs(norm2((xk(1:3,ik0)-xk(1:3,ik))*tpiba)-norm2(q1(:)))
       endif
    enddo
    write(*,*) 'gw_debug w1',w1(:)
    !do iq1 = 1, gw_nq_data(1)
    !   if(abs(norm2((xk(1:3,ik0)-xk(1:3,ik))*tpiba)-norm2(q1))<machine_eps*1e-6) 
    !enddo
! 2d simple interpolate prepare fixme
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
endif



    do ig1 = 1, gw_q_g_commonsubset_size
      do ig2 = 1, gw_q_g_commonsubset_size

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! simple interpolate
        !epstmp1=(gw_epsmat_full_data(1,ig1,ig2,1,1,iq1),&
        !         gw_epsmat_full_data(2,ig1,ig2,1,1,iq1))
        !epstmp2=(gw_epsmat_full_data(1,ig1,ig2,1,1,iq2),&
        !         gw_epsmat_full_data(2,ig1,ig2,1,1,iq2))

        !      eps_gw=gw_epsmat_full_data(:,ig1,ig2,1,1,iq1)*wq1+&
        !       gw_epsmat_full_data(:,ig1,ig2,1,1,iq2)*wq2
! simple interpolate
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


             if( interpolate_smallq1d) then
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!spline interpolate fixme 
!! change to 2d space matrix interpolate
!! change boundary condition

        !*gw_blat_data(1)
        !write(*,*) 'gw3.1 gind',ig1,ig2,gw_gind_rho2eps_data(1,1:5)
        !write(*,*) 'gw3.1 gind',ig1,ig2,gw_gind_rho2eps_data(2,1:5)
        !write(*,*) 'gw3.1 gind',ig1,ig2,gw_gind_rho2eps_data(3,1:5)
        !write(*,*) 'gw3.1',gw_q_g_commonsubset_indinrho(1:5)
        !write(*,*) 'gw3.1',gw_gind_rho2eps_data(1,1:5)
        !write(*,*) 'gw3.1',ig1,ig2
                do iq1=1,gw_nq_data_q0(1)
        !write(*,*) 'gw3.1.1',iq1, gind_gw_eps2,gw_q_g_commonsubset_indinrho(ig2),gw_gind_rho2eps_data(gw_q_g_commonsubset_indinrho(ig2),iq1)
                   gind_gw_eps1=gw_gind_rho2eps_data_q0(gw_q_g_commonsubset_indinrho_q0(ig1),iq1)
                   gind_gw_eps2=gw_gind_rho2eps_data_q0(gw_q_g_commonsubset_indinrho_q0(ig2),iq1)
        !write(*,*) 'gw3.1.2',iq1
                   if  (gind_gw_eps2>gw_nmtx_data_q0(iq1).or. gind_gw_eps2>gw_nmtx_data_q0(iq1)  )  &
write(*,*) 'gindex of eps qpts messedup'
        !write(*,*) 'gw3.1.3',1,gind_gw_eps1,gind_gw_eps2,1,1,iq1
        !write(*,*) 'gw3.1.3',gw_epsmat_full_data(1,gind_gw_eps1,gind_gw_eps2,1,1,iq1)
                   epsint_q0_tmp1(iq1)=gw_epsmat_full_data_q0(1,gind_gw_eps1,gind_gw_eps2,1,1,iq1)
        !write(*,*) 'gw3.1.3',iq1
                   epsint_q0_tmp2(iq1)=gw_epsmat_full_data_q0(2,gind_gw_eps1,gind_gw_eps2,1,1,iq1)
        !write(*,*) 'gw3.1.4',iq1
                enddo
        !write(*,*) 'gw3.2',ig1,ig2
                call  spline(gw_qabs_q0(:),epsint_q0_tmp1(:),0.0_DP,0.0_DP,epsint_q0_tmp3(:))
                epsinttmp1s= splint(gw_qabs_q0(:),epsint_q0_tmp1(:),epsint_q0_tmp3(:),deltakG_para)
                if (deltakG_para>maxval(gw_qabs_q0(:)))  epsinttmp1s=minval(epsint_q0_tmp1(:))
        
                call  spline(gw_qabs_q0(:),epsint_q0_tmp2(:),0.0_DP,0.0_DP,epsint_q0_tmp4(:))
                epsinttmp2s= splint(gw_qabs_q0(:),epsint_q0_tmp2(:),epsint_q0_tmp4(:),deltakG_para)
                if (deltakG_para>maxval(gw_qabs_q0(:)))  epsinttmp2s=minval(epsint_q0_tmp2(:))
        !        epsmat_inted(gw_gind_rho2eps_data(ig1,iq1),gw_gind_rho2eps_data(ig2,iq1))=complex(epsinttmp1s,epsinttmp2s)
                epsmat_inted(ig1,ig2)=complex(epsinttmp1s,epsinttmp2s)
        
!!spline interpolate fixme 
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
endif

  if (interpolate_2d) then
if(sum(w1(:))<machine_eps) then
write(*,*) 'eps 2d interpolation error'
stop -1
endif
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! 2d simple interpolate  fixme
                 do iq1 = 1, gw_nq_data_q1(1)
                   gind_gw_eps1=gw_gind_rho2eps_data_q1(gw_q_g_commonsubset_indinrho_q1(ig1),iq1)
                   gind_gw_eps2=gw_gind_rho2eps_data_q1(gw_q_g_commonsubset_indinrho_q1(ig2),iq1)
                   epsinttmp1s=gw_epsmat_full_data_q1(1,gind_gw_eps1,gind_gw_eps2,1,1,iq1)
                   epsinttmp2s=gw_epsmat_full_data_q1(2,gind_gw_eps1,gind_gw_eps2,1,1,iq1)
                   epsmat_inted(ig1,ig2)=epsmat_inted(ig1,ig2)+complex(epsinttmp1s,epsinttmp2s)*w1(iq1)
                 enddo
                 epsmat_inted(ig1,ig2)=epsmat_inted(ig1,ig2)/sum(w1(:))
! 2d simple interpolate  fixme
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 endif
 
        write(*,*) 'gw_debug epsmat_inted ig1,ig2,q',epsmat_inted(ig1,ig2),'ig1',ig1,'ig2',ig2,deltakG_para
               
              enddo
            enddo

! get interpolated eps matrix
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! get w(g)
!write(*,*) 'gw4'
    allocate(w_gw(ngk(ik0)))
    w_gw(:)=0.0

    qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
q2d_coeff=(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    DO ig1 = 1, ngk(ik0)
      Do ig2=1, ngk(ik)
           icount=icount+1
           deltakG=norm2(g(1:3,igk_k(ig1,ik0))&
                      -g(1:3,igk_k(ig2,ik))&
                      +xk(1:3,ik0)-xk(1:3,ik))*tpiba
           !w_gw(ig1)=w_gw(ig1)+epsmat_inted(gind_psi2rho_gw(ig1),gind_psi2rho_gw(ig2))*(tpi/(deltakG))
           w_gw(ig1)=w_gw(ig1)+epsmat_inted(gind_psi2rho_gw(ig1),gind_psi2rho_gw(ig2))*4*pi/(deltakG**2)*q2d_coeff
      Enddo

write(*,*) 'gw_debug W_gw vs q, ig1, g, w',ig1,norm2(g(1:3,igk_k(ig1,ik0))),w_gw(ig1) ,abs(w_gw(ig1) )
    Enddo
 
! get w(g)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!GW
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 
 
    allocate(eps_data_dy(size(eps_data(1,:))))
    call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))
    mcharge1=0
    mcharge2=0.00
    mcharge3=0.00
    icount=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1, ngk(ik)
           mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
           icount=icount+1
           deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
                      -g(1:2,igk_k(ig2,ik))&
                      +xk(1:2,ik0)-xk(1:2,ik))*tpiba

             deltakG_para=deltakG
             epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG_para)
             if (deltak>maxval(eps_data(1,:)))      epsk=minval(eps_data(2,:))
           mcharge1=mcharge1+mcharge0*tpi/deltakG
           mcharge2=mcharge2+mcharge0*tpi/(deltakG**2+k0screen**2)**0.5
           mcharge3=mcharge3+mcharge0*tpi/(deltakG)*epsk
      Enddo
    Enddo
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    write(*,*)  'Mcharge2DnoLFAns noki->kf ',ik0,ik, mcharge1, abs(mcharge1),icount
    write(*,*)  'Mcharge2DnoLFAs  noki->kf ',ik0,ik, mcharge2, abs(mcharge2),icount , 'k0screen', k0screen
    write(*,*)  'Mcharge2DnoLFAes noki->kf ',ik0,ik, mcharge3, abs(mcharge3),icount , 'epsk', epsk
    
    
    
    mcharge1=0
    mcharge2=0
    mcharge3=0
    mcharge4=0
    mcharge5=0
    mcharge6=0
    mcharge1gw=0
    mcharge2gw=0
    mcharge3gw=0
    mcharge4gw=0
    mcharge5gw=0
    mcharge6gw=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1, ngk(ik)
    
         mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
         deltakG=norm2(g(:,igk_k(ig1,ik0))&
                    -g(:,igk_k(ig2,ik))&
                    +xk(:,ik0)-xk(:,ik))*tpiba
    

         qxy=norm2(g(1:2,igk_k(ig1,ik0))&
                    -g(1:2,igk_k(ig2,ik))&
                    +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    
         qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
              xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba

             epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),qxy)
 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 ! bug, should be epsk(q)=epsk(q_//)
             !epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
             if (deltak>maxval(eps_data(1,:)))      epsk=minval(eps_data(2,:))
q2d_coeff=(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))

             mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)
             mcharge2=mcharge2+mcharge0*4*pi/(deltakG**2+k0screen**2)
             mcharge3=mcharge3+mcharge0*4*pi/(deltakG**2)*epsk
! write(*,*) 'mcharge3',mcharge3,mcharge0,4*pi,(deltakG**2),epsk
             mcharge4=mcharge4+mcharge0*4*pi/(deltakG**2)            *q2d_coeff
             mcharge5=mcharge5+mcharge0*4*pi/(deltakG**2+k0screen**2)*q2d_coeff
             mcharge6=mcharge6+mcharge0*4*pi/(deltakG**2)*epsk       *q2d_coeff



             do iq = 1,ngk(ik0) 
               if (norm2(g(1:3,igk_k(iq,ik0))-(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<machine_eps) then
                 mcharge1gw=mcharge1gw+mcharge0*w_gw(iq)
                 mcharge2gw=mcharge2gw+mcharge0*w_gw(iq)            *q2d_coeff
                 write(*,*) 'gw_debug W in M, ig1,ig2,iq,g1,g2,q,w_gw(iq)',&
           ig1,ig2,iq,g(:,igk_k(ig1,ik0)),g(:,igk_k(ig2,ik)) ,g(1:3,igk_k(iq,ik0)),w_gw(iq) 
               endif
            
             Enddo
      Enddo
    Enddo
    mcharge1gw=mcharge1/dffts%nnr
    mcharge2gw=mcharge2/dffts%nnr
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    mcharge4=mcharge4/dffts%nnr
    mcharge5=mcharge5/dffts%nnr
    mcharge6=mcharge6/dffts%nnr
    write(*,*)  'Mcharge3DnoLFAgw    0ki->kf ',ik0,ik,    mcharge1gw, abs(mcharge1gw)
    write(*,*)  'Mcharge3DnoLFAns    0ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    write(*,*)  'Mcharge3DnoLFAs     0ki->kf ',ik0,ik,    mcharge2, abs(mcharge2) , 'k0screen', k0screen
    write(*,*)  'Mcharge3DnoLFAes    0ki->kf ',ik0,ik,    mcharge3, abs(mcharge3) , 'epsk', epsk
    write(*,*)  'Mcharge3DcutnoLFAgw 0ki->kf ',ik0,ik,    mcharge2gw, abs(mcharge2gw)
    write(*,*)  'Mcharge3DcutnoLFAns 0ki->kf ',ik0,ik,    mcharge4, abs(mcharge4)
    write(*,*)  'Mcharge3DcutnoLFAs  0ki->kf ',ik0,ik,    mcharge5, abs(mcharge5) , 'k0screen', k0screen
    write(*,*)  'Mcharge3DcutnoLFAes 0ki->kf ',ik0,ik,    mcharge6, abs(mcharge6) , 'epsk', epsk
    
    END SUBROUTINE calcmdefect_charge_nolfa
    


    !SUBROUTINE calcmdefect_charge_2dnolfa(ibnd0,ibnd,ik0,ik)
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !!k0screen=tpiba*0.01
    !mcharge1=0
    !mcharge2=0.00
    !icount=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !       mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !       icount=icount+1
    !       deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
    !                  -g(1:2,igk_k(ig2,ik))&
    !                  +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !       mcharge1=mcharge1+mcharge0*tpi/deltakG
    !       mcharge2=mcharge2+mcharge0*tpi/(deltakG**2+k0screen**2)**0.5
    !  Enddo
    !Enddo
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
    !write(*,*)  'Mcharge2DnoLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1),icount
    !write(*,*)  'Mcharge2DnoLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2),icount , 'k0screen', k0screen
    !
    !END SUBROUTINE calcmdefect_charge_2dnolfa
    !
    !SUBROUTINE calcmdefect_charge_3dnolfa(ibnd0,ibnd,ik0,ik)
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !!k0screen=tpiba*0.01
    !Nlzcutoff=dffts%nr3/2
    !lzcutoff=Nlzcutoff*alat/dffts%nr1
    !
    !mcharge1=0
    !mcharge2=0
    !mcharge3=0
    !mcharge4=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !
    !     mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !     deltakG=norm2(g(:,igk_k(ig1,ik0))&
    !                -g(:,igk_k(ig2,ik))&
    !                +xk(:,ik0)-xk(:,ik))*tpiba
    !
    !     qxy=norm2(g(1:2,igk_k(ig1,ik0))&
    !                -g(1:2,igk_k(ig2,ik))&
    !                +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !
    !     qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
    !          xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba

    !         mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)
    !         mcharge2=mcharge2+mcharge0*4*pi/(deltakG**2+k0screen**2)
    !         mcharge3=mcharge3+mcharge0*4*pi/(deltakG**2)&
    !           *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    !         mcharge4=mcharge4+mcharge0*4*pi/(deltakG**2+k0screen**2)&
    !           *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    !  Enddo
    !Enddo
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
    !mcharge3=mcharge3/dffts%nnr
    !mcharge4=mcharge4/dffts%nnr
    !write(*,*)  'Mcharge3DnoLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    !write(*,*)  'Mcharge3DnoLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2) , 'k0screen', k0screen
    !write(*,*)  'Mcharge3DcutnoLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
    !write(*,*)  'Mcharge3DcutnoLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4) , 'k0screen', k0screen
    !
    !END SUBROUTINE calcmdefect_charge_3dnolfa
    
    !SUBROUTINE calcmdefect_charge_3dlfa(ibnd0,ibnd,ik0,ik)
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !!k0screen=tpiba*0.01
    !Nlzcutoff=dffts%nr3/2
    !lzcutoff=Nlzcutoff*alat/dffts%nr1
    !mcharge0=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !    if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<eps) then
    !         mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !    endif
    !  Enddo
    !Enddo
    !deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    !qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
    !mcharge1=mcharge0*4*pi/(deltak**2)
    !mcharge2=mcharge0*4*pi/(deltak**2+k0screen**2)
    !mcharge3=mcharge0*4*pi/(deltak**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    !mcharge4=mcharge0*4*pi/(deltak**2+k0screen**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    ! 
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
    !mcharge3=mcharge3/dffts%nnr
    !mcharge4=mcharge4/dffts%nnr
    !write(*,*)  'Mcharge3DLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    !write(*,*)  'Mcharge3DLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2) , 'k0screen', k0screen
    !write(*,*)  'Mcharge3DcutLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
    !write(*,*)  'Mcharge3DcutLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4) , 'k0screen', k0screen
    ! 
    !END SUBROUTINE calcmdefect_charge_3dlfa
    !
    !SUBROUTINE calcmdefect_charge_qehlfa(ibnd0,ibnd,ik0,ik)
    !use splinelib, only: dosplineint,spline,splint
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !real(DP) , allocatable::  eps_data_dy(:)
    !real(DP) :: epsk
    !!k0screen=tpiba*0.01
    !allocate(eps_data_dy(size(eps_data(1,:))))
    !call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))

    !mcharge0=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !    if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
    !         mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !     
    !    endif
    !  Enddo
    !Enddo

    !deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    !epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltak)
    !if (deltak>0.2)      epsk=minval(eps_data(2,:))


    !mcharge1=mcharge0*tpi/deltak*epsk
    !mcharge1=mcharge1/dffts%nnr
    !write(*,*)  'Mcharge2DLFAes ki->kf'   ,ik0,ik,   mcharge1, abs(mcharge1), 'epsk', epsk

    !mcharge0=0
    !mcharge1=0
    !mcharge2=0
    !mcharge0=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !    if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<eps) then
    !         mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !     
    !    endif
    !  Enddo
    !Enddo

    !deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    !epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltak)
    !if (deltak>0.2)      epsk=minval(eps_data(2,:))
  
   !! if (deltak>0.2) then
   !!        !epsk=0.0
   !! endif

    !qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
    !mcharge1=mcharge0*4*pi/(deltak**2)*epsk
    !mcharge2=mcharge0*4*pi/(deltak**2)*epsk*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    ! 
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
 
    !
    !write(*,*)  'Mcharge3DLFAes ki->kf',ik0,ik,   mcharge1, abs(mcharge1) , 'epsk', epsk
    !write(*,*)  'Mcharge3DcutLFAes ki->kf'   ,ik0,ik,   mcharge2, abs(mcharge2) , 'epsk', epsk

 
    !END SUBROUTINE calcmdefect_charge_qehlfa
     
    !SUBROUTINE calcmdefect_charge_qehnolfa(ibnd0,ibnd,ik0,ik)
    !use splinelib, only: dosplineint,spline,splint
    !COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    !INTEGER :: ibnd, ik, ik0,ibnd0
    !real(DP) , allocatable::  eps_data_dy(:)
    !real(DP) :: epsk
    !!k0screen=tpiba*0.01
    !allocate(eps_data_dy(size(eps_data(1,:))))
    !call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))


    !mcharge0=0
    !mcharge1=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)

    !         deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
    !                  -g(1:2,igk_k(ig2,ik))&
    !                  +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !         epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
    !         if (deltakG>0.2)      epsk=minval(eps_data(2,:))
    !         mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !         mcharge1=mcharge1+mcharge0*tpi/deltakG*epsk
    !     
    !  Enddo
    !Enddo


    !mcharge1=mcharge1/dffts%nnr
    !write(*,*)  'Mcharge2DnoLFAes ki->kf   '   ,ik0,ik,   mcharge1, abs(mcharge1),'epsk',epsk


    !mcharge0=0
    !mcharge1=0
    !mcharge2=0
    !DO ig1 = 1, ngk(ik0)
    !  Do ig2=1, ngk(ik)
    !
    !    mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
    !    deltakG=norm2(g(:,igk_k(ig1,ik0))&
    !               -g(:,igk_k(ig2,ik))&
    !               +xk(:,ik0)-xk(:,ik))*tpiba
    !
    !    qxy=norm2(g(1:2,igk_k(ig1,ik0))&
    !               -g(1:2,igk_k(ig2,ik))&
    !               +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    !    qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
    !         xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
    !    epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
    !    if (deltakG>0.2) epsk=minval(eps_data(2,:))

    !    mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)*epsk
    !! write(*,*) 'mcharge1',mcharge1,mcharge0,4*pi,(deltakG**2),epsk
    !    mcharge2=mcharge2+mcharge0*4*pi/(deltakG**2)*epsk&
    !      *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
 
    !  Enddo
    !Enddo
    !
    !mcharge1=mcharge1/dffts%nnr
    !mcharge2=mcharge2/dffts%nnr
    !write(*,*)  'Mcharge3DnoLFAes ki->kf  ',ik0,ik,   mcharge1, abs(mcharge1),'epsk',epsk
    !write(*,*)  'Mcharge3DcutnoLFAes ki->kf     '   ,ik0,ik,   mcharge2, abs(mcharge2),'epsk',epsk

    !END SUBROUTINE calcmdefect_charge_qehnolfa
    



    subroutine calcmdefect_ml_rs_noncolin(ibnd0,ibnd,ik0,ik, V_0, V_loc)

      USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
      INTEGER :: ibnd, ik, ik0,ibnd0
      type(V_file) :: V_0
      real(DP) :: V_loc(:,:)


      !write(*,*) V_loc(20:40,1)
      !write(*,*) V_loc(20:40,2)
      !write(*,*) V_0%plot(20:40)
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!! vl in real super2prim, module
      auxr(:) =  vrs(:,1)
      psiprod(:)=0.00
      vgk_perturb(:)=0.00
      ml_up=0
      ml_down=0
      d1=((1.0/dffts%nr1*at(1,1))*(xk(1,ik)-xk(1,ik0)) +&
          (1.0/dffts%nr1*at(2,1))*(xk(2,ik)-xk(2,ik0)) +&
          (1.0/dffts%nr1*at(3,1))*(xk(3,ik)-xk(3,ik0)) )*tpi 
      d2=((1.0/dffts%nr2*at(1,2))*(xk(1,ik)-xk(1,ik0)) +&
          (1.0/dffts%nr2*at(2,2))*(xk(2,ik)-xk(2,ik0)) +&
          (1.0/dffts%nr2*at(3,2))*(xk(3,ik)-xk(3,ik0)) )*tpi 
      d3=((1.0/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
          (1.0/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
          (1.0/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0)) )*tpi 
      
      psic2(1:dffts%nnr) = (0.d0,0.d0)
      psic1(1:dffts%nnr) = (0.d0,0.d0)
      psic4(1:dffts%nnr) = (0.d0,0.d0)
      psic3(1:dffts%nnr) = (0.d0,0.d0)

      DO ig = 1, ngk(ikk)
         psic2 (dffts%nl (igk_k(ig,ikk) ) ) = evc2 (ig, ibnd)
      ENDDO
      DO ig = 1, ngk(ik0)
         psic1 (dffts%nl (igk_k(ig,ik0) ) ) = evc1 (ig, ibnd0)
      ENDDO

      DO ig = 1, ngk(ikk)
         psic4 (dffts%nl (igk_k(ig,ikk) ) ) = evc2 (ig+npwx, ibnd)
      ENDDO
      DO ig = 1, ngk(ik0)
         psic3 (dffts%nl (igk_k(ig,ik0) ) ) = evc1 (ig+npwx, ibnd0)
      ENDDO

      

      CALL invfft ('Wave', psic2, dffts)
      CALL invfft ('Wave', psic1, dffts)
      CALL invfft ('Wave', psic4, dffts)
      CALL invfft ('Wave', psic3, dffts)
      
      !write(*,*) psic1(1:10)
      !write(*,*) psic2(1:10)
      !write(*,*) psic3(1:10)
      !write(*,*) psic4(1:10)
    
      arg=0
      inr=0
      do irz =0, V_0%nr3-1
      ir3mod=irz-(irz/(dffts%nr3))*dffts%nr3
      do iry =0, V_0%nr2-1
      ir2mod=iry-(iry/(dffts%nr2))*dffts%nr2
      do irx =0, V_0%nr1-1
      ir1mod=irx-(irx/(dffts%nr1))*dffts%nr1
      
      arg=irz*d3+iry*d2+irx*d1
      !!!!!!!!!!!!!!!!!!!!!!!!!!!
      !move vloc center 
      !!!!!!!!!!!!!!!!!!!!!!!!!!!
      
      arg=tpi*(real(irx)/dffts%nr1*at(1,1)+real(iry)/dffts%nr2*at(1,2)+real(irz)/dffts%nr3*at(1,3))*(xk(1,ik)-xk(1,ik0)) +&
          tpi*(real(irx)/dffts%nr1*at(2,1)+real(iry)/dffts%nr2*at(2,2)+real(irz)/dffts%nr3*at(2,3))*(xk(2,ik)-xk(2,ik0)) +&
          tpi*(real(irx)/dffts%nr1*at(3,1)+real(iry)/dffts%nr2*at(3,2)+real(irz)/dffts%nr3*at(3,3))*(xk(3,ik)-xk(3,ik0))   
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      ! shift arg center
      arg=irz*d3+(iry-iry/(V_0%nr2/2+1)*V_0%nr2)*d2+(irx-irx/(V_0%nr1/2+1)*V_0%nr1)*d1
      !arg=irz*d3+(iry-iry/(dffts%nr2/2+1)*dffts%nr1)*d2+(irx-irx/(dffts%nr1/2+1)*dffts%nr1)*d1
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !arg=irz*d3+iry*d2+irx*d1
      
      phase=CMPLX(COS(arg),SIN(arg),kind=dp)
      inr=inr+1
      irnmod=(ir3mod)*dffts%nr1*dffts%nr2+(ir2mod)*dffts%nr1+ir1mod+1
      ml_up=ml_up+CONJG(psic1(irnmod))*psic2(irnmod)*phase!*V_loc(inr, 1)
      ml_down=ml_down+CONJG(psic3(irnmod))*psic4(irnmod)*phase!*V_loc(inr, 2)

      if ( irnmod<0 .or. irnmod>dffts%nnr ) then
         write (*,*) 'grid mismatch', irnmod, dffts%nnr 
      endif
      
      
      if (irz==dffts%nr3/2) then
              argt= atan2(real(CONJG(psic1(irnmod))*psic2(irnmod)*phase),aimag(CONJG(psic1(irnmod))*psic2(irnmod)*phase))
              argt2= atan2(real(CONJG(psic1(irnmod))*psic2(irnmod)),aimag(CONJG(psic1(irnmod))*psic2(irnmod)))
              if (argt<0) argt=argt+tpi
      endif
  
         
      enddo
      enddo
      enddo
      ml_up=ml_up/dffts%nnr
      ml_down=ml_down/dffts%nnr
      write (*,1001) 'Ml_up ki->kf ',ik0,ik, ml_up, abs(ml_up)
      write (*,1001) 'Ml_down ki->kf ',ik0,ik,  ml_down, abs(ml_down)
      write (*,1002) 'Ml ki->kf ',ik0,ik,  ml_up+ml_down, abs(ml_up+ml_down)
  1001 format(A16,I9,I9," ( ",e17.9," , ",e17.9," ) ",e17.9)
  1002 format(A16,I9,I9," ( ",e17.9," , ",e17.9," ) ",e17.9/)
     
      
      
   end subroutine calcmdefect_ml_rs_noncolin


 
    SUBROUTINE calcmdefect_mnl_ks_noncolin(ibnd0,ibnd,ik0,ik, V_d, V_p)
    
      USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
      USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
       
      INTEGER :: ibnd, ik, ik0,ibnd0
      type(V_file) :: V_d, V_p
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!! initialization
      nkb_perturb=0
  
  
      DO nt_perturb = 1, V_d%ntyp
         DO na_perturb = 1, V_d%nat
            IF(V_d%ityp (na_perturb) == nt_perturb)THEN
                nkb_perturb = nkb_perturb + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      
      
      CALL allocate_bec_type ( nkb, nbnd, becp )
      CALL allocate_bec_type ( nkb, nbnd, becp1 )
      CALL allocate_bec_type ( nkb, nbnd, becp2 )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
      ALLOCATE(vkb_perturb(npwx,nkb_perturb))
      
      !!!!!! initialization
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
      CALL calbec ( ngk(ik), vkb, evc, becp )
      
      CALL init_us_2_perturb (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,V_d%nat,V_d%ityp,V_d%tau,nkb_perturb)
      CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
      
      CALL init_us_2_perturb (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,V_d%nat,V_d%ityp,V_d%tau,nkb_perturb)
      CALL calbec ( ngk(ik), vkb_perturb, evc2, becp2_perturb )
      
      
      ijkb0 = 0
      mnl_d=0
      mnltot=0
      DO nt_perturb = 1, V_d%ntyp
         DO na_perturb = 1, V_d%nat
            IF(V_d%ityp (na_perturb) == nt_perturb)THEN
               DO ih = 1, nh (nt_perturb)
                  ikb = ijkb0 + ih
                  IF(gamma_only)THEN
                     mnl_d=mnl_d+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                        * dvan(ih,ih,nt_perturb)
                  ELSE
                     mnl_d=mnl_d+conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan(ih,ih,nt_perturb) &
                           + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan(ih,ih,nt_perturb)
                  ENDIF
                  DO jh = ( ih + 1 ), nh(nt_perturb)
                     jkb = ijkb0 + jh
                     IF(gamma_only)THEN
                        mnl_d=mnl_d + &
                           (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                              becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                            * dvan(ih,jh,nt_perturb)
                     ELSE
                        mnl_d=mnl_d + &
                           (conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd)+&
                            conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd))&
                            * dvan(ih,jh,nt_perturb) &
                            + &
                            (conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd)+&
                             conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd))&
                             * dvan(ih,jh,nt_perturb)

                     ENDIF
      
                  ENDDO
      
               ENDDO
               ijkb0 = ijkb0 + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      mnltot=mnltot+mnl_d*wg(ibnd,ik)!

      
       
      CALL deallocate_bec_type (  becp )
      CALL deallocate_bec_type (  becp1 )
      CALL deallocate_bec_type (  becp2 )
      CALL deallocate_bec_type (  becp_perturb )
      CALL deallocate_bec_type (  becp1_perturb )
      CALL deallocate_bec_type (  becp2_perturb )
      DEALLOCATE(vkb_perturb)

      nkb_perturb=0
  
  
      DO nt_perturb = 1, V_p%ntyp
         DO na_perturb = 1, V_p%nat
            IF(V_p%ityp (na_perturb) == nt_perturb)THEN
                nkb_perturb = nkb_perturb + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      
      
      CALL allocate_bec_type ( nkb, nbnd, becp )
      CALL allocate_bec_type ( nkb, nbnd, becp1 )
      CALL allocate_bec_type ( nkb, nbnd, becp2 )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
      ALLOCATE(vkb_perturb(npwx,nkb_perturb))
      
      !!!!!! initialization
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
      CALL calbec ( ngk(ik), vkb, evc, becp )
      
      CALL init_us_2_perturb (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,V_p%nat,V_p%ityp,V_p%tau,nkb_perturb)
      CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
      
      CALL init_us_2_perturb (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,V_p%nat,V_p%ityp,V_p%tau,nkb_perturb)
      CALL calbec ( ngk(ik), vkb_perturb, evc2, becp2_perturb )
      
      
      ijkb0 = 0
      mnl_p=0
      mnltot=0
      DO nt_perturb = 1, V_p%ntyp
         DO na_perturb = 1, V_p%nat
            IF(V_p%ityp (na_perturb) == nt_perturb)THEN
               DO ih = 1, nh (nt_perturb)
                  ikb = ijkb0 + ih
                  IF(gamma_only)THEN
                     mnl_p=mnl_p+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                        * dvan(ih,ih,nt_perturb)
                  ELSE
                     mnl_p=mnl_p+conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan(ih,ih,nt_perturb) &
                           + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan(ih,ih,nt_perturb)
                  ENDIF
                  DO jh = ( ih + 1 ), nh(nt_perturb)
                     jkb = ijkb0 + jh
                     IF(gamma_only)THEN
                        mnl_p=mnl_p + &
                           (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                              becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                            * dvan(ih,jh,nt_perturb)
                     ELSE
                        mnl_p=mnl_p + &
                           (conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd)+&
                            conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd))&
                            * dvan(ih,jh,nt_perturb) &
                            + &
                            (conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd)+&
                             conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd))&
                             * dvan(ih,jh,nt_perturb)

                     ENDIF
      
                  ENDDO
      
               ENDDO
               ijkb0 = ijkb0 + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      mnltot=mnltot+mnl_p*wg(ibnd,ik)!
       
      CALL deallocate_bec_type (  becp )
      CALL deallocate_bec_type (  becp1 )
      CALL deallocate_bec_type (  becp2 )
      CALL deallocate_bec_type (  becp_perturb )
      CALL deallocate_bec_type (  becp1_perturb )
      CALL deallocate_bec_type (  becp2_perturb )
      DEALLOCATE(vkb_perturb)
  1001 format(A16,I9,I9, " ( ",e17.9," , ",e17.9," ) ",e17.9)
  1002 format(A16,I9,I9," ( ",e17.9," , ",e17.9," ) ",e17.9/)
      write (stdout,1001) 'Mnl_d ki->kf ', ik0,ik, mnl_d, abs(mnl_d)
      write (stdout,1001) 'Mnl_p ki->kf ', ik0,ik, mnl_p, abs(mnl_p)
      write (stdout,1002) 'Mnl ki->kf ', ik0,ik, mnl_d-mnl_p, abs(mnl_d-mnl_p)
      END SUBROUTINE calcmdefect_mnl_ks_noncolin

      SUBROUTINE calcmdefect_mnl_ks_soc(ibnd0,ibnd,ik0,ik, V_d, V_p)
    
         USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
         USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
          
         INTEGER :: ibnd, ik, ik0,ibnd0
         type(V_file) :: V_d, V_p
         !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         !!!!!! initialization
         nkb_perturb=0
     
     
         DO nt_perturb = 1, V_d%ntyp
            DO na_perturb = 1, V_d%nat
               IF(V_d%ityp (na_perturb) == nt_perturb)THEN
                   nkb_perturb = nkb_perturb + nh (nt_perturb)
               ENDIF
            ENDDO
         ENDDO
         
         
         CALL allocate_bec_type ( nkb, nbnd, becp )
         CALL allocate_bec_type ( nkb, nbnd, becp1 )
         CALL allocate_bec_type ( nkb, nbnd, becp2 )
         CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
         CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
         CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
         ALLOCATE(vkb_perturb(npwx,nkb_perturb))
         
         !!!!!! initialization
         !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
         CALL calbec ( ngk(ik), vkb, evc, becp )
         
         CALL init_us_2_perturb (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,V_d%nat,V_d%ityp,V_d%tau,nkb_perturb)
         CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
         
         CALL init_us_2_perturb (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,V_d%nat,V_d%ityp,V_d%tau,nkb_perturb)
         CALL calbec ( ngk(ik), vkb_perturb, evc2, becp2_perturb )
         
         ijkb0 = 0
         mnl_d=0
         mnltot=0
   
         DO nt_perturb = 1, V_d%ntyp
            DO na_perturb = 1, V_d%nat
               IF(V_d%ityp (na_perturb) == nt_perturb)THEN
                  DO ih = 1, nh (nt_perturb)
                     ikb = ijkb0 + ih
                     IF(gamma_only)THEN
                        mnl_d=mnl_d+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                           * dvan_so(ih,ih,1,nt_perturb)
                     ELSE
                        !write(*,*) dvan_so(ih,ih,1:4,nt_perturb)
                        mnl_d=mnl_d+&
                           conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan_so(ih,ih,1,nt_perturb)&
                           + conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan_so(ih,ih,2,nt_perturb)&
                           + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan_so(ih,ih,3,nt_perturb)&
                           + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan_so(ih,ih,4,nt_perturb)
                     ENDIF
                     DO jh = ( ih + 1 ), nh(nt_perturb)
                        jkb = ijkb0 + jh
                        IF(gamma_only)THEN
                           mnl_d=mnl_d + &
                              (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                                 becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                               * dvan_so(ih,jh,1,nt_perturb)
                        ELSE
                           !write(*,*) 'test'
                           !write(*,*) dvan_so(ih,jh,1:4,nt_perturb)
                           !write(*,*) dvan_so(jh,ih,1:4,nt_perturb)
                           mnl_d=mnl_d + &
                              conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd) &
                               * dvan_so(ih,jh,1,nt_perturb) &
                               + &
                               conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd) &
                               * dvan_so(jh,ih,1,nt_perturb) &

                               + &

                               conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd) &
                               * dvan_so(ih,jh,2,nt_perturb) &
                               + &
                               conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd) &
                               * dvan_so(jh,ih,2,nt_perturb) &

                               + &

                               conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd) &
                               * dvan_so(ih,jh,3,nt_perturb) &
                               + &
                               conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd) &
                               * dvan_so(jh,ih,3,nt_perturb) &

                               + &

                               conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd) &
                               * dvan_so(ih,jh,4,nt_perturb) &
                               + &
                               conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd) &
                               * dvan_so(jh,ih,4,nt_perturb) 
                              
                        ENDIF
         
                     ENDDO
                     
                  enddo
                  ijkb0 = ijkb0 + nh(nt_perturb)
               endif
            enddo
         enddo
         mnltot=mnltot+mnl_d*wg(ibnd,ik)


      CALL deallocate_bec_type (  becp )
      CALL deallocate_bec_type (  becp1 )
      CALL deallocate_bec_type (  becp2 )
      CALL deallocate_bec_type (  becp_perturb )
      CALL deallocate_bec_type (  becp1_perturb )
      CALL deallocate_bec_type (  becp2_perturb )
      DEALLOCATE(vkb_perturb)

      nkb_perturb=0
  
  
      DO nt_perturb = 1, V_p%ntyp
         DO na_perturb = 1, V_p%nat
            IF(V_p%ityp (na_perturb) == nt_perturb)THEN
                nkb_perturb = nkb_perturb + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      
      
      CALL allocate_bec_type ( nkb, nbnd, becp )
      CALL allocate_bec_type ( nkb, nbnd, becp1 )
      CALL allocate_bec_type ( nkb, nbnd, becp2 )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp1_perturb )
      CALL allocate_bec_type ( nkb_perturb, nbnd, becp2_perturb )
      ALLOCATE(vkb_perturb(npwx,nkb_perturb))
      
      !!!!!! initialization
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
      CALL calbec ( ngk(ik), vkb, evc, becp )
      
      CALL init_us_2_perturb (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,V_p%nat,V_p%ityp,V_p%tau,nkb_perturb)
      CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
      
      CALL init_us_2_perturb (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,V_p%nat,V_p%ityp,V_p%tau,nkb_perturb)
      CALL calbec ( ngk(ik), vkb_perturb, evc2, becp2_perturb )
      
      
      ijkb0 = 0
      mnl_p=0
      mnltot=0
      DO nt_perturb = 1, V_p%ntyp
         DO na_perturb = 1, V_p%nat
            IF(V_p%ityp (na_perturb) == nt_perturb)THEN
               DO ih = 1, nh (nt_perturb)
                  ikb = ijkb0 + ih
                  IF(gamma_only)THEN
                     mnl_p=mnl_p+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                        * dvan_so(ih,ih,1,nt_perturb)
                  ELSE
                     mnl_p=mnl_p&
                     + conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan_so(ih,ih,1,nt_perturb) &
                     + conjg(becp1_perturb%nc(ikb,1,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan_so(ih,ih,2,nt_perturb) &
                     + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,1,ibnd) * dvan_so(ih,ih,3,nt_perturb) &
                     + conjg(becp1_perturb%nc(ikb,2,ibnd0))*becp2_perturb%nc(ikb,2,ibnd) * dvan_so(ih,ih,4,nt_perturb)
                  ENDIF
                  DO jh = ( ih + 1 ), nh(nt_perturb)
                     jkb = ijkb0 + jh
                     IF(gamma_only)THEN
                        mnl_p=mnl_p + &
                           (becp1%r(ikb,ibnd0)*becp2%r(jkb,ibnd)+&
                              becp1%r(jkb,ibnd0)*becp2%r(ikb,ibnd))&
                            * dvan_so(ih,jh,1,nt_perturb)
                     ELSE
                        mnl_p=mnl_p + &
                           conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd) &
                           * dvan_so(ih,jh,1,nt_perturb) &
                           + &
                           conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd) &
                           * dvan_so(jh,ih,1,nt_perturb) &

                           + &

                           conjg(becp1_perturb%nc(ikb, 1, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd) &
                           * dvan_so(ih,jh,2,nt_perturb) &
                           + &
                           conjg(becp1_perturb%nc(jkb, 1, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd) &
                           * dvan_so(jh,ih,2,nt_perturb) &

                           + &

                           conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 1, ibnd) &
                           * dvan_so(ih,jh,3,nt_perturb) &
                           + &
                           conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 1, ibnd) &
                           * dvan_so(jh,ih,3,nt_perturb) &

                           + &

                           conjg(becp1_perturb%nc(ikb, 2, ibnd0))*becp2_perturb%nc(jkb, 2, ibnd) &
                           * dvan_so(ih,jh,4,nt_perturb) &
                           + &
                           conjg(becp1_perturb%nc(jkb, 2, ibnd0))*becp2_perturb%nc(ikb, 2, ibnd) &
                           * dvan_so(jh,ih,4,nt_perturb) 

                     ENDIF
      
                  ENDDO
      
               ENDDO
               ijkb0 = ijkb0 + nh (nt_perturb)
            ENDIF
         ENDDO
      ENDDO
      mnltot=mnltot+mnl_p*wg(ibnd,ik)!
       
      CALL deallocate_bec_type (  becp )
      CALL deallocate_bec_type (  becp1 )
      CALL deallocate_bec_type (  becp2 )
      CALL deallocate_bec_type (  becp_perturb )
      CALL deallocate_bec_type (  becp1_perturb )
      CALL deallocate_bec_type (  becp2_perturb )
      DEALLOCATE(vkb_perturb)
  1001 format(A16,I9,I9, " ( ",e17.9," , ",e17.9," ) ",e17.9)
  1002 format(A16,I9,I9," ( ",e17.9," , ",e17.9," ) ",e17.9/)
      write (stdout,1001) 'Mnl_d ki->kf ', ik0,ik, mnl_d, abs(mnl_d)
      write (stdout,1001) 'Mnl_p ki->kf ', ik0,ik, mnl_p, abs(mnl_p)
      write (stdout,1002) 'Mnl ki->kf ', ik0,ik, mnl_d-mnl_p, abs(mnl_d-mnl_p)
         
         END SUBROUTINE calcmdefect_mnl_ks_soc
END subroutine calcmdefect
