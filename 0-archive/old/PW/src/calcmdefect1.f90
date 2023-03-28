subroutine calcmdefect()  
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! mpi
USE mp_images,     ONLY : nimage
USE mp_bands,      ONLY : nbgrp
USE mp_pools,      ONLY : npool
USE mp_pools, ONLY: inter_pool_comm, intra_pool_comm, nproc_pool, me_pool
USE mp_bands, ONLY: intra_bgrp_comm
USE mp, ONLY: mp_sum, mp_gather, mp_bcast, mp_get

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
USE wavefunctions, ONLY : evc,evc1,evc2,evc3,evc4, psic,psic1,psic2
USE fft_types, ONLY:  fft_index_to_3d

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! io
USE io_global, ONLY: stdout, ionode, ionode_id
USE io_files, ONLY: nd_nmbr, nwordwfc, iunwfc, prefix, tmp_dir, seqopn, iuntmp
USE buffers,          ONLY : open_buffer,get_buffer, close_buffer, save_buffer
use input_parameters, only: vperturb_filename,eps_filename, &
kpoint_initial ,kpoint_final ,bnd_initial ,bnd_final ,&
calcmlocal ,calcmnonlocal ,calcmcharge 



IMPLICIT NONE


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! control
INTEGER, EXTERNAL :: find_free_unit
INTEGER :: tmp_unit
INTEGER  :: ios
INTEGER, PARAMETER :: n_overlap_tests = 12
REAL(dp), PARAMETER :: eps = 1.d-4
INTEGER, PARAMETER :: io = 77, iob = 78

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! scf
INTEGER :: npw, ig, ibnd, ik, ispin, nbndup, nbnddown, &
nk , ikk,ikk0,  inr, ig1, ig2
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
COMPLEX(DP) :: mnl, ml,mltot,mltot1,mltot2,mnltot,psicnorm,psicprod,enl1
LOGICAL :: offrange
REAL(dp)::arg
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
integer :: nepslines
real(DP),allocatable:: eps_data (:,:)

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

IF ( use_calcmdefect ) THEN
    call calcmdefect_all()
ENDIF

CONTAINS 
    SUBROUTINE calcmdefect_all()! initialization and call M subroutines 

    write (*,*) 'enter calcmdefect module'

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !extra function: not fully implemented
    ALLOCATE (idx (ngm) )
    ALLOCATE (igtog (ngm) )
    ALLOCATE (gtoig (ngm) )

    ALLOCATE (aux(dfftp%nnr))
    ALLOCATE(auxr(dfftp%nnr))
    ALLOCATE(psiprod(dfftp%nnr))
    ALLOCATE(vgk(dfftp%nnr))
    ALLOCATE(vgk_perturb(dfftp%nnr))
    ALLOCATE( auxg( dfftp%ngm ) )
    allocate(evc1(npwx,nbnd))
    allocate(evc2(npwx,nbnd))
    allocate(psic1(dfftp%nnr))
    allocate(psic2(dfftp%nnr))
    allocate(evc3(npwx,nbnd))
    allocate(evc4(npwx,nbnd))
    allocate(mlat2(dfftp%nr3))
    allocate(mlat1(dfftp%nr3))

    idx(:) = 0
    igtog(:) = 0
    IF( lsda )THEN
       nbndup = nbnd
       nbnddown = nbnd
       nk = nks/2
    ELSE
       nbndup = nbnd
       nbnddown = 0
       nk = nks
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


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! extra data read in, not used
    IF ( npool > 1 .or. nimage > 1 .or. nbgrp > 1 ) &
      CALL errore('calcmdefect', 'pool/band/image parallelization not (yet) implemented',1)
    IF ( noncolin .OR. lspinorb ) &
      CALL errore('calcmdefect', 'noncollinear/spinorbit magnetism not (yet) implemented',2)
    tmp_unit = find_free_unit()
    OPEN(unit=tmp_unit,file = trim(tmp_dir)//'calcmdefect.dat',status='old',err=20)
    20 continue
    !    READ(tmp_unit,inputpp,iostat=ios)
    CLOSE(tmp_unit)
    ! extra data read in, not used
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! vloc.dat read
    iunpot_perturb=99 
    filpot_perturb=vperturb_filename
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
    read (iunpot_perturb, '(i4,3x,a2,3x,f5.2)') &
            (nt_perturb, atm_perturb(nt_perturb), zv_perturb(nt_perturb), nt_perturb=1, ntyp_perturb)
    read (iunpot_perturb, *) (ndum_perturb,  (tau_perturb (ipol_perturb, na_perturb), ipol_perturb = 1, 3), &
            ityp_perturb(na_perturb), na_perturb = 1, nat_perturb)
    read (iunpot_perturb, * ) (plot_perturb (ir_perturb), ir_perturb = 1, nr1_perturb * nr2_perturb * nr3_perturb)
    tau_perturb(:,:)=tau_perturb(:,:)*alat_perturb/alat

    !debug output
    !write (*,*) 'dv readin-vrs', sum(plot_perturb(:)-vrs(:,1))
    !write (*,*) 'dv readin-vrs: , sum(plot_perturb(:)),sum(vrs(:,1)),sum(plot_perturb(:))-sum(vrs(:,1))'
    !write (*,*)  sum(plot_perturb(:)),sum(vrs(:,1)),sum(plot_perturb(:))-sum(vrs(:,1))
    !write (*,*) 'at-perturb', at_perturb
    !write (*,*) 'nr1_perturb ', nr1_perturb
    !write (*,*) 'nr2_perturb ', nr2_perturb
    !write (*,*) 'nr3_perturb ', nr3_perturb
    !write (*,*) 'at', at(:,1)
    !write (*,*) 'at', at(:,2)
    !write (*,*) 'at', at(:,3)
    !write (*,*) 'dfftp%nr1 ', dfftp%nr1
    !write (*,*) 'dfftp%nr2 ', dfftp%nr2
    !write (*,*) 'dfftp%nr3 ', dfftp%nr3
    !write (*,*) 'dffts%nr1 ', dffts%nr1
    !write (*,*) 'dffts%nr2 ', dffts%nr2
    !write (*,*) 'dffts%nr3 ', dffts%nr3
    !write (*,*) 'dv readin-vrs', plot_perturb(:)-vrs(:,1)
    !write (*,*) 'dv readin-vrs', vrs(:,1)
    !write (*,*) 'dv readin-vrs', plot_perturb(:)
    
    !!!!!! vloc.dat read
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!! eps read 
    iunpot_perturb=99 
    filpot_perturb='eps.dat'
    open (unit = iunpot_perturb, file = filpot_perturb, form = 'formatted', &
         status = 'old', err = 99, iostat = ios_perturb)
    
    read (iunpot_perturb, '(a)') title_perturb
    read (iunpot_perturb, * ) nepslines
    
    allocate(eps_data(2,nepslines))
    do ig= 1, nepslines
         read (iunpot_perturb, * ) eps_data(1,ig),eps_data(2,ig)
    enddo
    ! debug output
    !write (*,*) 'eps lines  ', nepslines
    !write (*,*) 'eps data  ', eps_data(1,1),eps_data(2,1)
    !write (*,*) 'eps data  ', eps_data(1,2),eps_data(2,2)
    !write (*,*) 'eps data  ', eps_data(1,3),eps_data(2,3)
    !write (*,*) 'eps data  ', eps_data(1,7),eps_data(2,7)
    
    !!!!!! eps read 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    
    
    
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!eloc from rho*vloc
    mnl=0
    DO ig = 1, dffts%nnr
       mnl=mnl+rho%of_r(ig,1)
    ENDDO
    write(*,*), 'rhotot',mnl, ml/mnl*8
    
    ml=0
    auxr(:) =  vltot(:)
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*), 'el=rho*vltot', ml
    
    ml=0
    auxr(:) = v%of_r(:,1) 
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*), 'el=rho*v%of_r', ml
    
    ml=0
    auxr(:) = vrs(:,1)
    DO ig = 1, dffts%nnr
       ml=ml+rho%of_r(ig,1)*auxr(ig)
    ENDDO
    write(*,*), 'el=rho*vrs', ml
    !!!!!!!!!!!eloc from rho*vloc
   
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ! loop through k points
    write (*,*) 'start M calculation k loop'
    ibnd0=bnd_initial
    ibnd=bnd_final
    DO ik0=kpoint_initial,kpoint_final
     DO ik = 1, nk
      DO ispin = 1, nspin
        ikk = ik + nk*(ispin-1)
        ikk0 = ik0 + nk*(ispin-1)
        
        CALL get_buffer ( evc2, nwordwfc, iunwfc, ikk )
        CALL get_buffer ( evc1, nwordwfc, iunwfc, ikk0 )
    
        call calcmdefect_ml_rs(ibnd0,ibnd,ikk0,ikk)
        !call calcmdefect_ml_rd(ibnd0,ibnd,ikk0,ikk)
        !call calcmdefect_ml_ks(ibnd0,ibnd,ikk0,ikk)
        !call calcmdefect_ml_kd(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_mnl_ks(ibnd0,ibnd,ikk0,ikk)
        !call calcmdefect_mnl_kd(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_charge_2dlfa(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_charge_2dnolfa(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_charge_3dlfa(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_charge_3dnolfa(ibnd0,ibnd,ikk0,ikk)
        call calcmdefect_charge_qeh(ibnd0,ibnd,ikk0,ikk)
    
      enddo
     enddo
    enddo
    
    END SUBROUTINE calcmdefect_all

    SUBROUTINE calcmdefect_ml_rs(ibnd0,ibnd,ik0,ik)
    INTEGER :: ibnd, ik, ik0,ibnd0
    psiprod(:)=0.00
    vgk_perturb(:)=0.00
    ml=0
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
    
    arg=0
    inr=0
    do irz =0, nr3_perturb-1
      ir3mod=irz-(irz/(dffts%nr3))*dffts%nr3
      do iry =0, nr2_perturb-1
        ir2mod=iry-(iry/(dffts%nr2))*dffts%nr2
        do irx =0, nr1_perturb-1
          ir1mod=irx-(irx/(dffts%nr1))*dffts%nr1
          arg=irz*d3+iry*d2+irx*d1
          
          phase=CMPLX(COS(arg),SIN(arg),kind=dp)
          inr=inr+1
          irnmod=(ir3mod)*dffts%nr1*dffts%nr2+(ir2mod)*dffts%nr1+ir1mod+1
          ml=ml+CONJG(psic1(irnmod))*psic2(irnmod)*plot_perturb(inr)*phase
          if ( irnmod<0 .or. irnmod>dffts%nnr ) then
              write (*,*) 'grid mismatch', irnmod
          endif
        enddo
      enddo
    enddo
    
    ml=ml/dffts%nnr
    write (*,*) 'Ml ki->kf ',ik0,ik, ml, abs(ml)
    
    END SUBROUTINE calcmdefect_ml_rs

    SUBROUTINE calcmdefect_mnl_ks(ibnd0,ibnd,ik0,ik)
    
    USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
    USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
    
    INTEGER :: ibnd, ik, ik0,ibnd0
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
    
    !!!!!! initialization
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   
    
    
    npw = ngk(ik0)
    CALL init_us_2_perturb (npw, igk_k(1,ik0), xk (1, ik0), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
    CALL calbec ( npw, vkb_perturb, evc1, becp1_perturb )
    npw = ngk(ik)
    CALL init_us_2_perturb (npw, igk_k(1,ik), xk (1, ik), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
    CALL calbec ( npw, vkb_perturb, evc2, becp2_perturb )
   
    ijkb0 = 0
    mnl=0
    mnltot=0
    DO nt_perturb = 1, ntyp_perturb
       DO na_perturb = 1, nat_perturb
          IF(ityp_perturb (na_perturb) == nt_perturb)THEN
             DO ih = 1, nh (nt_perturb)
                ikb = ijkb0 + ih
                IF(gamma_only)THEN
                   mnl=mnl+becp1%r(ikb,ibnd0)*becp2%r(ikb,ibnd) &
                      * dvan(ih,ih,nt_perturb)
                ELSE
                   mnl=mnl+conjg(becp1_perturb%k(ikb,ibnd0))*becp2_perturb%k(ikb,ibnd) &
                      * dvan(ih,ih,nt_perturb)
                ENDIF
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
                          * dvan(ih,jh,nt_perturb) 
                   ENDIF
    
                ENDDO
    
             ENDDO
             ijkb0 = ijkb0 + nh (nt_perturb)
          ENDIF
       ENDDO
    ENDDO
    mnltot=mnltot+mnl*wg(ibnd,ik)
     
    CALL deallocate_bec_type (  becp )
    CALL deallocate_bec_type (  becp1 )
    CALL deallocate_bec_type (  becp2 )
    CALL deallocate_bec_type (  becp_perturb )
    CALL deallocate_bec_type (  becp1_perturb )
    CALL deallocate_bec_type (  becp2_perturb )
    DEALLOCATE(vkb_perturb)
    write (stdout,*) 'Mnl ki->kf ', ik0,ik, mnl, abs(mnl)
    END SUBROUTINE calcmdefect_mnl_ks
 
    SUBROUTINE calcmdefect_charge_2dlfa(ibnd0,ibnd,ik0,ik)
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    INTEGER :: ibnd, ik, ik0,ibnd0
    write (*,*) 'enter M charge calculation', ibnd, ik, ik0,ibnd0
    k0screen=tpiba*0.01
    
    mcharge0=0
    icount=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
        if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
           icount=icount+1
           mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
        endif
      Enddo
    Enddo
    deltak=((xk(1,ik)-xk(1,ik0))**2&
           +(xk(2,ik)-xk(2,ik0))**2)**0.5*tpiba
    
    mcharge2=mcharge0*tpi/(deltak**2+k0screen**2)**0.5
    mcharge1=mcharge0*tpi/deltak
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    write(*,*)   'Mcharge2DLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1)
    write(*,*)   'Mcharge2DLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2)
    END SUBROUTINE calcmdefect_charge_2dlfa
    
    SUBROUTINE calcmdefect_charge_2dnolfa(ibnd0,ibnd,ik0,ik)
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    INTEGER :: ibnd, ik, ik0,ibnd0
    k0screen=tpiba*0.01
    mcharge1=0
    mcharge2=0.00
    icount=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
           mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
           icount=icount+1
           deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
                      -g(1:2,igk_k(ig2,ik))&
                      +xk(1:2,ik0)-xk(1:2,ik))*tpiba
           mcharge1=mcharge1+mcharge0*tpi/deltakG
           mcharge2=mcharge2+mcharge0*tpi/(deltakG**2+k0screen**2)**0.5
      Enddo
    Enddo
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    write(*,*)  'Mcharge2DnoLFAns ki->kf ',ik0,ik, mcharge1, abs(mcharge1),icount
    write(*,*)  'Mcharge2DnoLFAs  ki->kf ',ik0,ik, mcharge2, abs(mcharge2),icount
    
    END SUBROUTINE calcmdefect_charge_2dnolfa
    
    SUBROUTINE calcmdefect_charge_3dnolfa(ibnd0,ibnd,ik0,ik)
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    INTEGER :: ibnd, ik, ik0,ibnd0
    k0screen=tpiba*0.01
    Nlzcutoff=dffts%nr3/2
    lzcutoff=Nlzcutoff*alat/dffts%nr1
    
    mcharge1=0
    mcharge2=0
    mcharge3=0
    mcharge4=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
    
             mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
             deltakG=norm2(g(:,igk_k(ig1,ik0))&
                        -g(:,igk_k(ig2,ik))&
                        +xk(:,ik0)-xk(:,ik))*tpiba
    
             qxy=norm2(g(1:2,igk_k(ig1,ik0))&
                        -g(1:2,igk_k(ig2,ik))&
                        +xk(1:2,ik0)-xk(1:2,ik))*tpiba
    
             qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
                  xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
                 mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)
                 mcharge2=mcharge2+mcharge0*4*pi/(deltakG**2+k0screen**2)
                 mcharge3=mcharge3+mcharge0*4*pi/(deltakG**2)&
                   *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
                 mcharge4=mcharge4+mcharge0*4*pi/(deltakG**2+k0screen**2)&
                   *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
      Enddo
    Enddo
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    mcharge4=mcharge4/dffts%nnr
    write(*,*)  'Mcharge3DnoLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    write(*,*)  'Mcharge3DnoLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2)
    write(*,*)  'Mcharge3DcutnoLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
    write(*,*)  'Mcharge3DcutnoLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4)
    
    END SUBROUTINE calcmdefect_charge_3dnolfa
    
    SUBROUTINE calcmdefect_charge_3dlfa(ibnd0,ibnd,ik0,ik)
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    INTEGER :: ibnd, ik, ik0,ibnd0
    k0screen=tpiba*0.01
    mcharge0=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
        if (sum(abs(g(:,igk_k(ig1,ik0))-g(:,igk_k(ig2,ik))))<eps) then
             mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
        endif
      Enddo
    Enddo
    deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    qxy=norm2(xk(1:2,ik0)-xk(1:2,ik))*tpiba
    qz= (( xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
    mcharge1=mcharge0*2*pi/(deltak**2)
    mcharge2=mcharge0*4*pi/(deltak**2+k0screen**2)
    mcharge3=mcharge0*4*pi/(deltak**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
    mcharge4=mcharge0*4*pi/(deltak**2+k0screen**2)*(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
     
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    mcharge3=mcharge3/dffts%nnr
    mcharge4=mcharge4/dffts%nnr
    write(*,*)  'Mcharge3DLFAns ki->kf ',ik0,ik,    mcharge1, abs(mcharge1)
    write(*,*)  'Mcharge3DLFAs  ki->kf ',ik0,ik,    mcharge2, abs(mcharge2)
    write(*,*)  'Mcharge3DcutLFAns ki->kf ',ik0,ik, mcharge3, abs(mcharge3)
    write(*,*)  'Mcharge3DcutLFAs  ki->kf ',ik0,ik, mcharge4, abs(mcharge4)
     
    END SUBROUTINE calcmdefect_charge_3dlfa
    
    SUBROUTINE calcmdefect_charge_qeh(ibnd0,ibnd,ik0,ik)
    use splinelib, only: dosplineint,spline,splint
    COMPLEX(DP) ::  mcharge0,mcharge1,mcharge2,mcharge3,mcharge4
    INTEGER :: ibnd, ik, ik0,ibnd0
    real(DP) , allocatable::  eps_data_dy(:)
    real(DP) :: epsk
    k0screen=tpiba*0.01
    allocate(eps_data_dy(size(eps_data(1,:))))
    call spline(eps_data(1,:),eps_data(2,:),0.0_DP,0.0_DP,eps_data_dy(:))

    mcharge0=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
        if (sum(abs(g(1:2,igk_k(ig1,ik0))-g(1:2,igk_k(ig2,ik))))<eps) then
             mcharge0=mcharge0+conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
         
        endif
      Enddo
    Enddo

    deltak=norm2(xk(:,ik0)-xk(:,ik))*tpiba
    epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltak)
    if (deltak>0.2) then
           epsk=0.0
    endif


    mcharge1=mcharge0*tpi/deltak*epsk
    mcharge1=mcharge1/dffts%nnr
    write(*,*)  'Mcharge2DLFAes ki->kf'   ,ik0,ik,   mcharge1, abs(mcharge1)

    
    mcharge0=0
    mcharge1=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw

             deltakG=norm2(g(1:2,igk_k(ig1,ik0))&
                      -g(1:2,igk_k(ig2,ik))&
                      +xk(1:2,ik0)-xk(1:2,ik))*tpiba
             epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
             if (deltakG>0.2) then
                    epsk=0.0
             endif
             mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
             mcharge1=mcharge1+mcharge0*tpi/deltakG*epsk
         
      Enddo
    Enddo


    mcharge1=mcharge1/dffts%nnr
    write(*,*)  'Mcharge2DnoLFAes ki->kf'   ,ik0,ik,   mcharge1, abs(mcharge1)


    mcharge0=0
    mcharge1=0
    mcharge2=0
    DO ig1 = 1, ngk(ik0)
      Do ig2=1,npw
    
        mcharge0=conjg(evc1(ig1,ibnd0))*evc2(ig2,ibnd)
        deltakG=norm2(g(:,igk_k(ig1,ik0))&
                   -g(:,igk_k(ig2,ik))&
                   +xk(:,ik0)-xk(:,ik))*tpiba
    
        qxy=norm2(g(1:2,igk_k(ig1,ik0))&
                   -g(1:2,igk_k(ig2,ik))&
                   +xk(1:2,ik0)-xk(1:2,ik))*tpiba
        qz= ((g(3,igk_k(ig1,ik0))-g(3,igk_k(ig2,ik))+ &
             xk(3,ik0)-xk(3,ik))**2)**0.5*tpiba
        epsk= splint(eps_data(1,:),eps_data(2,:),eps_data_dy(:),deltakG)
        if (deltakG>0.2) then
               epsk=0.0
        endif

        mcharge1=mcharge1+mcharge0*4*pi/(deltakG**2)*epsk
        mcharge2=mcharge3+mcharge0*4*pi/(deltakG**2)*epsk&
          *(1-(cos(qz*lzcutoff)-sin(qz*lzcutoff)*qz/qxy)*exp(-(qxy*lzcutoff)))
 
      Enddo
    Enddo
    
    mcharge1=mcharge1/dffts%nnr
    mcharge2=mcharge2/dffts%nnr
    write(*,*)  'Mcharge3DcutnoLFAes ki->kf',ik0,ik,   mcharge1, abs(mcharge1)
    write(*,*)  'Mcharge3DnoLFAes ki->kf'   ,ik0,ik,   mcharge2, abs(mcharge2)

    END SUBROUTINE calcmdefect_charge_qeh
      
END subroutine calcmdefect
