function test_suite=test_surface_io()
% tests for surface input/output
%
% #   For CoSMoMVPA's copyright information and license terms,   #
% #   see the COPYING file distributed with CoSMoMVPA.           #

    initTestSuite;

function test_surface_dataset_gifti()
    if cosmo_skip_test_if_no_external('gifti')
        return;
    end
    save_and_load('gii');

function test_surface_dataset_niml_dset()
    if cosmo_skip_test_if_no_external('afni')
        return;
    end
    save_and_load('niml_dset');

function test_surface_dataset_bv_smp()
    if cosmo_skip_test_if_no_external('neuroelf')
        return;
    end
    save_and_load('bv_smp');

function test_surface_dataset_pymvpa()
    save_and_load('pymvpa');


function props=format2props(format)
    f2p=struct();
    f2p.gii.ext='.gii';
    f2p.gii.writer=@(fn,x)save(x,fn);
    f2p.gii.reader=@(fn)gifti(fn);
    f2p.gii.cleaner=@do_nothing;
    f2p.gii.isa=@(x)isa(x,'gifti');

    f2p.bv_smp.ext='.smp';
    f2p.bv_smp.writer=@(fn,x)x.SaveAs(fn);
    f2p.bv_smp.reader=@read_bv_and_bless;
    f2p.bv_smp.cleaner=@(x)x.ClearObject();
    f2p.bv_smp.isa=@(x)isa(x,'xff');

    f2p.niml_dset.ext='.niml.dset';
    f2p.niml_dset.writer=@(fn,x)afni_niml_writesimple(x,fn);
    f2p.niml_dset.reader=@(fn)afni_niml_readsimple(fn);
    f2p.niml_dset.cleaner=@do_nothing;
    f2p.niml_dset.isa=@(x)isstruct(x) && isfield(x,'node_indices');

    f2p.pymvpa.ext='.mat';
    f2p.pymvpa.writer=@write_mat_struct;
    f2p.pymvpa.reader=@import_struct_data_with_error_if_illegal;
    f2p.pymvpa.cleaner=@do_nothing;
    f2p.pymvpa.map2surface=@(x,fn)write_mat_struct(fn,...
                                cosmo_map2surface(x,'','format','pymvpa'));
    f2p.pymvpa.isa=@(x)isstruct(x) && ...
                    cosmo_isfield(x,{'samples'}) && ...
                    ~cosmo_isfield(x,'a.fdim');

    props=f2p.(format);

function x=read_bv_and_bless(fn)
    x=xff(fn);
    bless(x);

function x=do_nothing(x)
    % do nothing

function write_mat_struct(fn,s)
    save(fn,'-struct','s');

function s=import_struct_data_with_error_if_illegal(fn)
    try
        s=load(fn);
    catch
        error('Unable to read %s',fn);
    end

function save_and_load(format)
    ds=cosmo_synthetic_dataset('type','surface','nchunks',1);
    nfeatures=size(ds.samples,2);
    ds.fa.node_indices=ds.fa.node_indices(nonid_randperm(nfeatures));

    if ~strcmp(format,'bv_smp')
        % also permute node indices
        ds.a.fdim.values{1}=ds.a.fdim.values{1}(nonid_randperm(nfeatures));
    end

    ds.sa=struct();
    ds.sa.stats={'Ftest(3,4)';'Zscore()'};
    ds.sa.labels={'label1';'label2'};


    props=format2props(format);
    ext=props.ext;
    tmp_fn2=cosmo_make_temp_filename('_tmp',ext);

    cleaner=onCleanup(@()delete(tmp_fn2));

    if isfield(props,'map2surface')
        mapper=props.map2surface;
    else
        mapper=@cosmo_map2surface;
    end
    mapper(ds,tmp_fn2);
    ds2=cosmo_surface_dataset(tmp_fn2);

    assert_dataset_equal(ds,ds2,format);

    if strcmp(format,'bv_smp')
        ds2.a.fdim.values{1}=ds.a.fdim.values{1}(...
                                    nonid_randperm(nfeatures));
        assertExceptionThrown(@()cosmo_map2surface(ds2,tmp_fn2),'');
    end

    o=cosmo_map2surface(ds,['-' format]);
    writer=props.writer;
    reader=props.reader;

    writer(tmp_fn2,o);
    o2=reader(tmp_fn2);
    ds3=cosmo_surface_dataset(o2);

    assert_dataset_equal(ds,ds3,format);

    % extra format-specific tests
    switch format
        case 'gii'
            o3=gifti(struct('cdata',o2.cdata));
            ds4=cosmo_surface_dataset(o3);
            ds3.a.fdim.values{1}=1:nfeatures;
            assert_dataset_equal(ds3,ds4,format);
        case 'niml'
            o2=rmfield(o2,'node_indices');
            ds4=cosmo_surface_dataset(o2);
            ds3.a.fdim.values{1}=1:nfeatures;
            assert_dataset_equal(ds3,ds4,format);
    end

    % use format explicitly
    o4=cosmo_map2surface(ds,'','format',format);
    assert_isa_func=props.isa;
    assert_isa_func(o4);
    ds4=cosmo_surface_dataset(o4);
    assert_dataset_equal(ds,ds4,format);

    % test with dataset attributes
    targets=[3 4];
    chunks=5;
    ds4=cosmo_surface_dataset(ds,'targets',targets,'chunks',chunks);
    ds4_expected=ds;
    ds4_expected.sa.chunks=[chunks; chunks];
    ds4_expected.sa.targets=targets(:);
    assertEqual(ds4,ds4_expected);


    % make illegal dataset
    fid=fopen(tmp_fn2,'w');
    fprintf(fid,'foo');
    fclose(fid);

    switch format
        case 'bv_smp'
            exception_io_failed='xff:XFFioFailed';
            exception_bad_content='xff:BadFileContent';

        otherwise
            exception_io_failed='';
            exception_bad_content='';
    end

    assertExceptionThrown(@()reader(tmp_fn2),exception_io_failed);

    tmp_fn2=cosmo_make_temp_filename();
    assertExceptionThrown(@()reader(tmp_fn2),exception_bad_content);

function test_surface_io_exceptions()
    aet_in=@(varargin)assertExceptionThrown(@()...
                    cosmo_surface_dataset(varargin{:}),'');
    aet_out=@(varargin)assertExceptionThrown(@()...
                    cosmo_map2surface(varargin{:}),'');
    tmp_fn=cosmo_make_temp_filename();

    aet_in(tmp_fn);
    aet_in(struct());
    aet_in({});

    ds=cosmo_synthetic_dataset('type','surface');
    aet_out(struct,'-bv_smp');
    aet_out(struct,'-gii');
    aet_out(struct,'-niml_dset');
    aet_out(ds,tmp_fn);
    aet_out(ds,'-foo');
    aet_out(ds,struct());
    aet_out(ds,{});


function test_pymvpa_3d_string_array()
    py_ds=struct();
    py_ds.samples=rand(3,4);
    py_ds.fa.node_indices=[0,3,4,6];

    sa_labels={'foo';'bar';'foobaz'};
    sa_labels_3d=reshape(strvcat(sa_labels),[3 1 6]);
    py_ds.sa.labels=sa_labels_3d;

    ds=cosmo_surface_dataset(py_ds);
    assertEqual(ds.sa.labels,sa_labels);



function rp=nonid_randperm(n)
    assert(n>1);
    while true
        rp=randperm(n);
        if ~isequal(rp,1:n)
            return;
        end
    end

function assert_dataset_equal(x,y,format)
    mp=cosmo_align(y.fa.node_indices,x.fa.node_indices);
    mp2=cosmo_align(y.a.fdim.values{1},x.a.fdim.values{1});

    z=cosmo_slice(y,mp(mp2),2);
    z.a.fdim.values{1}=z.a.fdim.values{1}(mp2);
    assertEqual(x.a,z.a);
    assertEqual(x.fa,z.fa);
    assertElementsAlmostEqual(x.samples,z.samples,'absolute',1e-4);


    if ~strcmp(format,'gii')
        assertEqual(x.sa,z.sa);
    end





