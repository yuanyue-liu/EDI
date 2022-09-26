       
subroutine gw_eps_bcast(p_rank,p_source,gw_,gid,my_mpi_int,my_mpi_dp)
  USE kinds, ONLY: DP,sgl
  USE HDF5
  use edic_mod, only: gw_eps_data
    
  
  type(gw_eps_data),intent (inout) ,target:: gw_
  
  ! allocate(gw_%ng_data(h5dims1(1)))
  
  INTEGER :: n, root, ierr
  INTEGER :: datadims0
  INTEGER :: datadims1(1)
  INTEGER :: datadims2(2)
  INTEGER :: datadims3(3)
  INTEGER :: datadims4(4)
  INTEGER :: datadims5(5)
  INTEGER :: datadims6(6)
  INTEGER :: datasize
  integer,intent(in):: p_rank,p_source,gid,my_mpi_int,my_mpi_dp
  ! debug
  !!!!!!!!!!!!! ng
  !!write(*,*)'gw read 5.0 rank', p_rank,gid
  !!write(*,*)'gw read 5.1 rank', p_rank,gw_%ng_data 
  !!write(*,*)'gw read 5 rank1', gw_%ng_data, 1, MPI_integer, 0, mpi_comm_world, ierr
  !!call  mpi_barrier(gid)
  !!call flush(6)
  !!           CALL MPI_BCAST( gw_%ng_data, 1, MPI_integer, 0, mpi_comm_world, ierr )
  !!            CALL MPI_BCAST( gw_%ng_data, 1, my_MPI_int, 0, gid, ierr )
  !!write(*,*)'gw read 5 rank', p_rank,gw_%ng_data,MPI_comm_world 
  !!call  mpi_barrier(gid)
  !!call flush(6)
  !!write(*,*)'gw read 5.0 rank', p_rank,gid
  !!write(*,*)'gw read 5.1 rank', p_rank,gw_%ng_data 
  !!call  mpi_comm_rank(gid,p_rank,ik)
  !!call  mpi_comm_size(gid,p_size,ik)
  !write(*,*)'gw read 5.0 rank', p_rank,gid
  !write(*,*)'gw read 5.1 rank', p_rank,gw_%ng_data 
  !!call  mpi_barrier(gid)
  !!call flush(6)
  !allocate(datadims1(1))
  !if (p_rank==p_source)then
  !    datadims1=shape(gw_%ng_data)
  !    datasize=size(gw_%ng_data)
  !endif
  !!write(*,*)'gw read 5.2 rank', datasize, 1, MPI_integer, p_source, gid, ierr 
  !!write(*,*)'gw read 5.2 rank', datasize, 1, my_MPI_int, p_source, gid, ierr 
  !!call  mpi_barrier(gid)
  !!call flush(6)
  !CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  !
  !CALL MPI_BCAST( datadims1, 1,my_MPI_int, p_source, gid, ierr )
  !if(.not. allocated(gw_%ng_data))    allocate(gw_%ng_data(datadims1(1)))
  !
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%ng_data 
  ! CALL MPI_BCAST( gw_%ng_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%ng_data 
  !!!!!!!!!
  !
  !call  mpi_barrier(gid)
  !call flush(6)
  !deallocate(datadims1)
  !
  !!CALL MPI_BCAST( gw_%ng_data, 1, MPI_DOUBLE_PRECISION, root, gid, ierr )
  
  
  !ng
  if (p_rank==p_source)then
      datadims1=shape(gw_%ng_data)
      datasize=size(gw_%ng_data)
  endif
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims1, 1,my_MPI_int, p_source, gid, ierr )
  if(.not. allocated(gw_%ng_data))    allocate(gw_%ng_data(datadims1(1)))
  CALL MPI_BCAST( gw_%ng_data, datasize, my_MPI_int,p_source, gid, ierr )
  write(*,*)'gw read 5.3 rank', p_rank,gw_%ng_data 
  
  !nmtx_max
  if (p_rank==p_source)then
      datadims1=shape(gw_%nmtx_max_data)
      datasize=size(gw_%nmtx_max_data)
  endif
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims1, 1,my_MPI_int, p_source, gid, ierr )
  if(.not. allocated(gw_%nmtx_max_data))    allocate(gw_%nmtx_max_data(datadims1(1)))
  CALL MPI_BCAST( gw_%nmtx_max_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%nmtx_max_data 
  
  !'/eps_header/gspace/nmtx'      !i4 (nq,ng)
  if (p_rank==p_source)then
      datadims1=shape(gw_%nmtx_data)
      datasize=size(gw_%nmtx_data)
  endif
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims1, 1,my_MPI_int, p_source, gid, ierr )
  if(.not. allocated(gw_%nmtx_data))    allocate(gw_%nmtx_data(datadims1(1)))
  CALL MPI_BCAST( gw_%nmtx_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%nmtx_data 
  
  !'/eps_header/gspace/gind_eps2rho'      !i4 (nq,ng)
  if (p_rank==p_source)then
      datadims2=shape(gw_%gind_eps2rho_data)
      datasize=size(gw_%gind_eps2rho_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims2, size(datadims2),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2
  if(.not. allocated(gw_%gind_eps2rho_data))    allocate(gw_%gind_eps2rho_data(datadims2(1),datadims2(2)))
  !write(*,*)'gw read 5.3 rank', p_rank,shape(gw_%gind_eps2rho_data )
  CALL MPI_BCAST( gw_%gind_eps2rho_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%gind_eps2rho_data 
  
  !'/eps_header/gspace/gind_rho2eps'      !i4 (nq,ng)
  if (p_rank==p_source)then
      datadims2=shape(gw_%gind_rho2eps_data)
      datasize=size(gw_%gind_rho2eps_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims2, size(datadims2),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2
  if(.not. allocated(gw_%gind_rho2eps_data))    allocate(gw_%gind_rho2eps_data(datadims2(1),datadims2(2)))
  !write(*,*)'gw read 5.3 rank', p_rank,shape(gw_%gind_rho2eps_data )
  CALL MPI_BCAST( gw_%gind_rho2eps_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%gind_rho2eps_data 
  
  
  !'/mf_header/gspace/components'               !
  if (p_rank==p_source)then
      datadims2=shape(gw_%g_components_data)
      datasize=size(gw_%g_components_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims2, size(datadims2),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2
  if(.not. allocated(gw_%g_components_data))    allocate(gw_%g_components_data(datadims2(1),datadims2(2)))
  !write(*,*)'gw read 5.3 rank', p_rank,shape(gw_%g_components_data )
  CALL MPI_BCAST( gw_%g_components_data, datasize, my_MPI_int,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank', p_rank,gw_%g_components_data 
  
  
  
  !'/mf_header/crystal/bvec'               !
  if (p_rank==p_source)then
      datadims2=shape(gw_%bvec_data)
      datasize=size(gw_%bvec_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims2, size(datadims2),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2
  if(.not. allocated(gw_%bvec_data))    allocate(gw_%bvec_data(datadims2(1),datadims2(2)))
  !write(*,*)'gw read 5.3 rank shape bvec', p_rank,shape(gw_%bvec_data )
  CALL MPI_BCAST( gw_%bvec_data, datasize, my_MPI_dp,p_source, gid, ierr )
  write(*,*)'gw read 5.3 rank bvec', p_rank,gw_%bvec_data 
  
  
  
  !'/mf_header/crystal/blat'               !
  if (p_rank==p_source)then
      datadims1=shape(gw_%blat_data)
      datasize=size(gw_%blat_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims1,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims1, size(datadims1),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims1
  if(.not. allocated(gw_%blat_data))    allocate(gw_%blat_data(datadims1(1)))
  !write(*,*)'gw read 5.3 rank shape blat', p_rank,shape(gw_%blat_data )
  CALL MPI_BCAST( gw_%blat_data, datasize, my_MPI_dp,p_source, gid, ierr )
  write(*,*)'gw read 5.3 rank blat', p_rank,gw_%blat_data 
  
  
  !'/eps_header/qpoints/qpts'               !
  if (p_rank==p_source)then
      datadims2=shape(gw_%qpts_data)
      datasize=size(gw_%qpts_data)
  endif
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims2, size(datadims2),my_MPI_int, p_source, gid, ierr )
  !write(*,*)'gw read 5.3.0 rank', p_rank,datadims2
  if(.not. allocated(gw_%qpts_data))    allocate(gw_%qpts_data(datadims2(1),datadims2(2)))
  write(*,*)'gw read 5.3 rank shape qpts', p_rank,shape(gw_%qpts_data )
  CALL MPI_BCAST( gw_%qpts_data, datasize, my_MPI_dp,p_source, gid, ierr )
  write(*,*)'gw read 5.3 rank qpts', p_rank,gw_%qpts_data 
  
  
  
  !'/eps_header/qpoints/nq'               !
  if (p_rank==p_source)then
      datadims1=shape(gw_%nq_data)
      datasize=size(gw_%nq_data)
  endif
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims1, 1,my_MPI_int, p_source, gid, ierr )
  if(.not. allocated(gw_%nq_data))    allocate(gw_%nq_data(datadims1(1)))
  CALL MPI_BCAST( gw_%nq_data, datasize, my_MPI_int,p_source, gid, ierr )
  write(*,*)'gw read 5.3 rank nq', p_rank,gw_%nq_data 
  
  
  !'/mats/matrix-diagonal'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
  if (p_rank==p_source)then
      datadims3=shape(gw_%epsmat_diag_data)
      datasize=size(gw_%epsmat_diag_data)
  endif
  write(*,*)'gw read 5.3.0 rank', p_rank,datadims3,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims3, size(datadims3),my_MPI_int, p_source, gid, ierr )
  write(*,*)'gw read 5.3.0 rank', p_rank,datadims3
  if(.not. allocated(gw_%epsmat_diag_data))    allocate(gw_%epsmat_diag_data(datadims3(1),datadims3(2),datadims3(3)))
  write(*,*)'gw read 5.3 rank shape epsmat_diag', p_rank,shape(gw_%epsmat_diag_data )
  CALL MPI_BCAST( gw_%epsmat_diag_data, datasize, my_MPI_dp,p_source, gid, ierr )
  !write(*,*)'gw read 5.3 rank epsmat_diag', p_rank,gw_%epsmat_diag_data 
  
  
  !'/mats/matrix'                         !f8 (nq, 1,1, nmtx_max,nmtx_max,2)
  if (p_rank==p_source)then
      datadims6=shape(gw_%epsmat_full_data)
      datasize=size(gw_%epsmat_full_data)
  endif
  write(*,*)'gw read 5.3.0 rank', p_rank,datadims6,datasize
  CALL MPI_BCAST( datasize, 1, my_MPI_int, p_source, gid, ierr )
  CALL MPI_BCAST( datadims6, size(datadims6),my_MPI_int, p_source, gid, ierr )
  write(*,*)'gw read 5.3.0 rank', p_rank,datadims6
  if(.not. allocated(gw_%epsmat_full_data))then    
      allocate(gw_%epsmat_full_data(datadims6(1),datadims6(2),datadims6(3),datadims6(4),datadims6(5),datadims6(6)))
  endif
  write(*,*)'gw read 5.3 rank shape epsmat_full', p_rank,shape(gw_%epsmat_full_data )
  CALL MPI_BCAST( gw_%epsmat_full_data, datasize, my_MPI_dp,p_source, gid, ierr )
  !!write(*,*)'gw read 5.3 rank epsmat_full', p_rank,gw_%epsmat_full_data 
  
  
  
  
  !call  mpi_barrier(gid)
  !call flush(6)



contains 
  subroutine bcast_Data(p_rank,p_source,data_)
    integer,intent(in):: p_rank,p_source
    integer,intent(inout)::data_ 
  end subroutine bcast_Data

end subroutine gw_eps_bcast
