function [forward_model]=update_spatial_component(timeseries, sensor_movie, template, opts)

if ~isfield(opts,'bg_sub')
    opts.bg_sub=1;
end

[~, order]=sort(sum(template,2));

I=[];
J=[];
S=[];

for neur=1:size(template,1)
    neuron=order(neur);
    space=find(template(neuron,:));
    if ~isempty(space)
        involved_neurons=find(max(template(:,space),[],2));
        if opts.bg_sub==0
            temp=template(involved_neurons,space);
            if size(template,1)~=size(timeseries,1)
                disp('Error: template and timeseries have the wrong dimensions');
                return
            end
        else
            temp=zeros(length(involved_neurons)+1,length(space));
            temp(1:length(involved_neurons),:)=template(involved_neurons,space);
            temp(length(involved_neurons)+1,:)=ones(1,length(space));
            involved_neurons=[involved_neurons' size(timeseries,1)];
            if size(template,1)==size(timeseries,1)
                disp('Error: template and timeseries have the wrong dimensions');
                return
            end
        end
        Y=sensor_movie(space,:);
        opts.anti=1;        
        if opts.exact==0
            F=NONnegLSQ_gpu(timeseries(involved_neurons,:),[],Y,temp,opts);
        else
            A=timeseries(involved_neurons,:)';
            F=zeros(length(involved_neurons),size(space,2));
            for k_=1:length(space)
                
                idx=find(squeeze(temp(:,k_)));
                y=squeeze(Y(k_,:))';
                opts.Accy=0;
                x_=nnls(A(:,idx),y,opts);
                F(idx,k_)=x_;
            end
        end
        
        if size(involved_neurons,2)>=1
            template(:,space)=0;
            [iI, iJ, iS]=find(F);
            iJ=space(iJ);
            iI=involved_neurons(iI);
            iS=reshape(iS,length(iS),1);
            I=[I reshape(iI,1,[])];
            J=[J reshape(iJ,1,[])];
            S=[S' iS']';
        end
    end
    if strcmp(opts.display,'on')
    disp(neuron);
    end
end

gpuDevice([]);
S=double(S);
forward_model=sparse(I,J,S,size(timeseries,1),size(sensor_movie,1));

end