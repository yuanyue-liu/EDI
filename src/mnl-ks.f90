
    SUBROUTINE calcmdefect_mnl_ks(ibnd0,ibnd,ik0,ik,v_mnl)
    !SUBROUTINE calcmdefect_mnl_ks(ibnd0,ibnd,ik0,ik)
    !USE becmod, ONLY: becp,becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb, calbec, allocate_bec_type, deallocate_bec_type
    !USE cell_base,       ONLY : alat, ibrav, omega, at, bg, celldm, wmass
    
USE wvfct, ONLY: npwx, nbnd, wg, et
USE io_global, ONLY: stdout, ionode, ionode_id
USE uspp, ONLY: nkb, vkb, dvan
USE control_flags,    ONLY : gamma_only, io_level
USE kinds, ONLY: DP,sgl
!USE wavefunctions, ONLY : evc,evc1,evc2,evc3,evc4, psic, psic1, psic2, psic3, psic4
      Use edic_mod, Only : evc1,evc2,evc3,evc4,&
                               psic1, psic2, psic3, psic4
!use edic_mod, only: v_d,v_p
      Use edic_mod,   only: V_file
USE klist , ONLY: nks, nelec, xk, wk, degauss, ngauss, igk_k, ngk
    USE becmod, ONLY: becp, calbec, allocate_bec_type, deallocate_bec_type
    USE becmod, ONLY: becp1,becp2,becp_perturb,becp1_perturb,becp2_perturb 
    
    USE uspp_param, ONLY: nh
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
type(V_file):: v_mnl

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


    INTEGER :: ibnd, ik, ik0,ibnd0
nat_perturb=v_mnl%nat
ntyp_perturb=v_mnl%ntyp
ityp_perturb=v_mnl%ityp
tau_perturb=v_mnl%tau
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
!    CALL init_us_2 (ngk(ik), igk_k(1,ik), xk (1, ik), vkb)
!    CALL calbec ( ngk(ik), vkb, evc, becp )
    
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
    CALL init_us_2_sc (ngk(ik0), igk_k(1,ik0), xk (1, ik0), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
    CALL calbec ( ngk(ik0), vkb_perturb, evc1, becp1_perturb )
    
    !write (*,*) '1 ', shape(vkb_perturb),shape(evc1),ngk(ik0),npwx
    !write (*,*) 'evc1 ', evc1
    !write (*,*) 'vkb ', vkb
    !write (*,*) '1 ', shape(vkb_perturb),shape(becp1_perturb)
    
    !npw = ngk(ik)
    CALL init_us_2_sc (ngk(ik), igk_k(1,ik), xk (1, ik), vkb_perturb,nat_perturb,ityp_perturb,tau_perturb,nkb_perturb)
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
    
