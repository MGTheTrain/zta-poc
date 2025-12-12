### SPIFFE (Secure Production Identity Framework for Everyone)

SPIFFE is a universal identity system for software services. Instead of 
using passwords or IP addresses to identify services, SPIFFE gives each 
service a cryptographic identity (like a digital passport).

**Problem it solves**: In dynamic cloud environments, services move 
between machines, so IP-based security breaks. SPIFFE provides portable 
identity.

**How it works**: Each service gets an SVID (SPIFFE Verifiable Identity 
Document) - a short-lived certificate with a unique ID like 
`spiffe://cluster.local/ns/default/sa/payment-service`.

**Why Istio uses it**: Enables automatic mTLS between services without 
manual certificate management.