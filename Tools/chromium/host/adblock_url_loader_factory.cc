#include "adblock_url_loader_factory.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "mojo/public/cpp/bindings/receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "net/base/net_errors.h"
#include "net/url_request/redirect_info.h"
#include "url/origin.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/url_loader_completion_status.h"
#include "services/network/public/mojom/early_hints.mojom.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "services/network/public/mojom/url_loader.mojom.h"
#include "services/network/public/mojom/url_loader_factory.mojom.h"
namespace boaz {
namespace {
class Request final : public network::mojom::URLLoader,
                      public network::mojom::URLLoaderClient {
 public:
  Request(mojo::PendingReceiver<network::mojom::URLLoader> receiver,
          mojo::PendingRemote<network::mojom::URLLoaderClient> client,
          AdblockRequestContext context, AdblockDecider decide,
          const network::ResourceRequest& request)
      : receiver_(this, std::move(receiver)), client_(std::move(client)),
        context_(std::move(context)), decide_(std::move(decide)),
        method_(request.method), destination_(request.destination), resource_type_(request.resource_type) {
    receiver_.set_disconnect_handler(base::BindOnce(&Request::Destroy, weak_.GetWeakPtr()));
    client_.set_disconnect_handler(base::BindOnce(&Request::Destroy, weak_.GetWeakPtr()));
  }
  void Start(network::mojom::URLLoaderFactory* factory, int32_t id, uint32_t options,
             const network::ResourceRequest& request,
             const net::MutableNetworkTrafficAnnotationTag& annotation) {
    std::optional<GURL> rewrite;
    const int error = Evaluate(request.url, rewrite);
    if (error != net::OK) { Complete(error); return; }
    network::ResourceRequest forwarded = request;
    if (rewrite) forwarded.url = *rewrite;
    auto client_remote = downstream_client_.BindNewPipeAndPassRemote();
    downstream_client_.set_disconnect_handler(base::BindOnce(
        &Request::Complete, weak_.GetWeakPtr(), net::ERR_FAILED));
    factory->CreateLoaderAndStart(loader_.BindNewPipeAndPassReceiver(), id, options,
                                  forwarded, std::move(client_remote), annotation);
  }
 private:
  int Evaluate(const GURL& url, std::optional<GURL>& rewrite) {
    const auto decision = decide_.Run(url, method_, destination_, resource_type_, context_);
    switch (decision.action) {
      case AdblockDecision::Action::kAllow:
        return decision.rewritten_url || !decision.replacement_data_url.empty() ? net::ERR_NOT_IMPLEMENTED : net::OK;
      case AdblockDecision::Action::kBlock:
        return net::ERR_BLOCKED_BY_CLIENT;
      case AdblockDecision::Action::kRewrite: {
        if (!decision.rewritten_url || !decision.replacement_data_url.empty()) return net::ERR_NOT_IMPLEMENTED;
        const GURL& target = *decision.rewritten_url;
        if (!url.is_valid() || !target.is_valid() || !url.SchemeIsHTTPOrHTTPS() ||
            !target.SchemeIsHTTPOrHTTPS() ||
            !url::Origin::Create(url).IsSameOriginWith(url::Origin::Create(target)) ||
            url.path() != target.path() || url.username() != target.username() ||
            url.password() != target.password() || url.ref() != target.ref() ||
            url.has_ref() != target.has_ref() ||
            url.has_username() != target.has_username() || url.has_password() != target.has_password()) return net::ERR_NOT_IMPLEMENTED;
        rewrite = target;
        return net::OK;
      }
      case AdblockDecision::Action::kResourceReplacement:
      case AdblockDecision::Action::kUnsupported:
        return net::ERR_NOT_IMPLEMENTED;
    }
    return net::ERR_NOT_IMPLEMENTED;
  }
  void Destroy() { delete this; }
  void Complete(int error) { OnComplete(network::URLLoaderCompletionStatus(error)); }
  void FollowRedirect(network::HttpRequestHeadersUpdateParams params,
                      const std::optional<GURL>& new_url) override {
    std::optional<GURL> forwarded_url = pending_rewrite_;
    if (new_url) {
      // Evaluate a client override once. The downstream loader still validates
      // it against the original server redirect, including same-origin checks.
      forwarded_url = new_url;
      std::optional<GURL> rewrite;
      const int error = Evaluate(*new_url, rewrite);
      if (error != net::OK) { Complete(error); return; }
      if (rewrite) forwarded_url = *rewrite;
    }
    pending_rewrite_.reset();
    loader_->FollowRedirect(std::move(params), forwarded_url);
  }
  void SetPriority(net::RequestPriority priority, int32_t value) override {
    loader_->SetPriority(priority, value);
  }
  void OnReceiveEarlyHints(network::mojom::EarlyHintsPtr hints) override {
    client_->OnReceiveEarlyHints(std::move(hints));
  }
  void OnReceiveResponse(network::mojom::URLResponseHeadPtr head,
                         mojo::ScopedDataPipeConsumerHandle body,
                         std::optional<mojo_base::BigBuffer> metadata) override {
    client_->OnReceiveResponse(std::move(head), std::move(body), std::move(metadata));
  }
  void OnReceiveRedirect(const net::RedirectInfo& info,
                         network::mojom::URLResponseHeadPtr head) override {
    method_ = info.new_method;
    pending_rewrite_.reset();
    const int error = Evaluate(info.new_url, pending_rewrite_);
    if (error != net::OK) { Complete(error); return; }
    client_->OnReceiveRedirect(info, std::move(head));
  }
  void OnUploadProgress(int64_t current, int64_t total,
                        OnUploadProgressCallback callback) override {
    client_->OnUploadProgress(current, total, std::move(callback));
  }
  void OnTransferSizeUpdated(int32_t difference) override {
    client_->OnTransferSizeUpdated(difference);
  }
  void OnComplete(const network::URLLoaderCompletionStatus& status) override {
    loader_.reset(); downstream_client_.reset();
    client_->OnComplete(status);
    delete this;
  }
  mojo::Receiver<network::mojom::URLLoader> receiver_;
  mojo::Remote<network::mojom::URLLoaderClient> client_;
  mojo::Remote<network::mojom::URLLoader> loader_;
  mojo::Receiver<network::mojom::URLLoaderClient> downstream_client_{this};
  const AdblockRequestContext context_;
  const AdblockDecider decide_;
  std::string method_;
  std::optional<GURL> pending_rewrite_;
  const network::mojom::RequestDestination destination_;
  const int resource_type_;
  base::WeakPtrFactory<Request> weak_{this};
};
class Factory final : public network::mojom::URLLoaderFactory {
 public:
  Factory(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
          mojo::PendingRemote<network::mojom::URLLoaderFactory> downstream,
          AdblockRequestContext context, AdblockDecider decide)
      : downstream_(std::move(downstream)), context_(std::move(context)), decide_(std::move(decide)) {
    receivers_.Add(this, std::move(receiver));
    receivers_.set_disconnect_handler(base::BindRepeating(&Factory::Disconnected, base::Unretained(this)));
    downstream_.set_disconnect_handler(base::BindOnce(&Factory::Destroy, base::Unretained(this)));
  }
 private:
  void Disconnected() { if (receivers_.empty()) delete this; }
  void Destroy() { delete this; }
  void CreateLoaderAndStart(mojo::PendingReceiver<network::mojom::URLLoader> receiver,
      int32_t id, uint32_t options, const network::ResourceRequest& request,
      mojo::PendingRemote<network::mojom::URLLoaderClient> client,
      const net::MutableNetworkTrafficAnnotationTag& annotation) override {
    auto* proxy = new Request(std::move(receiver), std::move(client), context_, decide_, request);
    proxy->Start(downstream_.get(), id, options, request, annotation);
  }
  void Clone(mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver) override {
    receivers_.Add(this, std::move(receiver));
  }
  mojo::Remote<network::mojom::URLLoaderFactory> downstream_;
  mojo::ReceiverSet<network::mojom::URLLoaderFactory> receivers_;
  const AdblockRequestContext context_;
  const AdblockDecider decide_;
};
}
void BindAdblockURLLoaderFactory(
    mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
    mojo::PendingRemote<network::mojom::URLLoaderFactory> downstream,
    AdblockRequestContext context, AdblockDecider decide,
    scoped_refptr<base::SequencedTaskRunner> runner) {
  CHECK(runner); CHECK(decide); CHECK(receiver.is_valid()); CHECK(downstream.is_valid());
  runner->PostTask(FROM_HERE, base::BindOnce(
      [](mojo::PendingReceiver<network::mojom::URLLoaderFactory> receiver,
         mojo::PendingRemote<network::mojom::URLLoaderFactory> downstream,
         AdblockRequestContext context, AdblockDecider decide) {
        new Factory(std::move(receiver), std::move(downstream), std::move(context), std::move(decide));
      }, std::move(receiver), std::move(downstream), std::move(context), std::move(decide)));
}
}
